# Example Invocation:
#
#    gcc test.c -o test -g
#    TRACE_FUNCTIONS=fib TRACE_FILE=log gdb -x gdb_trace.py test
#    cat log
#
#  Log File Format:
#
#    ('call', Parent Call ID, Call ID, Breakpoint Name, Symbol Name, Arguments)
#    ('return', Call Id, Breakpoint Name, Return Value)
#    ('exit', Exit Code)

import gdb
import sys
import os

fd = open(os.environ.get('TRACE_FILE', "/tmp/log"), "w+")
def log(*args):
    fd.write(repr(args) + "\n")

trace_functions = [x.strip() for x in os.environ.get('TRACE_FUNCTIONS', 'main').split(',')]

def exit_handler(event):
    if hasattr(event, 'exit_code'):
        log('exit', event.exit_code)
    else:
        log('exit', None)
gdb.events.exited.connect(exit_handler)

def format_value(var, max_depth=30):
    try:
        str(var) # Invalid references
    except:
        return None

    if var is None or var.is_optimized_out or max_depth == 0:
        return None

    type = var.type.strip_typedefs()

    if type.code in (gdb.TYPE_CODE_INT, gdb.TYPE_CODE_ENUM, gdb.TYPE_CODE_CHAR):
        return {'type': str(var.type), 'value': int(var)}

    if type.code in (gdb.TYPE_CODE_FLT, ):
        return {'type': str(var.type), 'value': float(var)}

    if type.code in (gdb.TYPE_CODE_PTR,):
        # Do not derference types starting with _


        try:
            return {'type': str(var.type), 'value': var.string()}
        except gdb.error:
            pass
        deref = None
        if str(var.type)[0] != "_":
            try:
                deref = var.dereference()
                deref = format_value(deref, max_depth-1)
            except:
                deref = None
        return {'type': str(var.type), 'value': int(var), 'deref': deref}


    if type.code in (gdb.TYPE_CODE_STRUCT,):
        fields = {}
        for field in var.type.fields():
            fields[field.name] = format_value(var[field], max_depth-1)
        return {'type': str(var.type), 'value': fields}

    return {'type': str(var.type), 'value': None}


active_calls = []
call_id = 0

class FunctionBreakpoint(gdb.Breakpoint):
    def __init__(self, name):
        gdb.Breakpoint.__init__(self, name)
        self.silent = True
        self.name = name

    def stop(self):
        global call_id
        try:
            frame = gdb.newest_frame()
        except RuntimeError:
            return False
        pframe = frame
        pcall_id = None
        while pframe:
            found = False
            for pname, pcall_id in reversed(active_calls):
                if pname == pframe.name():
                    found = True
                    break
            if found:
                break
            pframe = pframe.older()
            pcall_id = None

        call_id += 1
        active_calls.append([frame.name(), call_id])


        try:
            arguments = [x for x in frame.block() if x.is_argument]
        except RuntimeError: # Cannot locate block or frame
            arguments = []
        arguments = {x.name: format_value(frame.read_var(x)) for x in arguments}
        log('call', pcall_id, call_id, self.name, frame.name(), arguments)
        # Break at finish of this function
        if frame.name() != 'main':
            FinishBreakpoint(frame, self.name, call_id)
        else: # main
            for fn in trace_functions:
                FunctionBreakpoint(fn)
        return False

class FinishBreakpoint (gdb.FinishBreakpoint):
    def __init__(self, frame, name, call_id):
        super().__init__(frame, True)
        self.frame = frame
        self.call_id = call_id
        self.name = name

    def stop (self):
        errno = None
        log('return', self.call_id, self.name,
            format_value(self.return_value),
        )
        active_calls.pop()
        return False # Do not Break

    def out_of_scope (self,):
        log('abort', self.name, self.call_id)

FunctionBreakpoint('main')
# gdb.execute('run')
# fd.close()
# gdb.execute('quit')
