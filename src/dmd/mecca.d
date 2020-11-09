module dmd.mecca;

import core.stdc.stdio: printf, fopen, fprintf, fclose;
import std.algorithm.iteration: map, each, filter;
import std.array: array;
import std.string: toStringz;
import core.stdc.string;
import std.json;

import std.stdio: writeln;

import dmd.visitor;
import dmd.dmodule;
import dmd.arraytypes;
import dmd.dtemplate;
import dmd.permissivevisitor;
import dmd.dsymbol;

auto Watch(string Type, string Param)
{
    const string decl = Type ~ " _"~Param ~ ";";
    const string getter = "@property auto " ~ Param ~ `(){ 
    import dmd.mecca:getBacktrace;
    this.tracing.bt ~= getBacktrace();
    return ` ~"_"~Param ~";}";
    const string setter = "@property nothrow void " ~ Param ~ "(" ~ Type ~ " x){ " ~ "_"~Param ~ "= x; }";
    return decl ~ setter ~ getter;
}

class ModuleDepGraph {
    class Node{
        TemplateInstance root;
        TemplateInstance[] children;
        bool visited;
        this(TemplateInstance r) {root = r;}
    }

    Module m;
    Node[TemplateInstance] nodes;

    this(Module m){
        this.m = m;
    }

    auto add(TemplateInstance ti){
        if(ti !in nodes)
            nodes[ti] = new Node(ti);
    }

    auto link(TemplateInstance src, TemplateInstance dst){
        nodes[src].children ~= dst;
    }

    auto topologicalSort(){
        Node[] result;

        void visit(Node n){
            assert(!n.visited);
            n.visited = true;
            n.children.
                map!(ti => nodes[ti]).
                filter!(child => !child.visited).
                each!visit;

            result ~= n;
        }

        nodes.values.filter!(n => !n.visited).each!visit;

        return result;
    }
}

extern(C++) class TempGraphVisitor: SemanticTimeTransitiveVisitor
{
    alias visit = SemanticTimeTransitiveVisitor.visit;
    ModuleDepGraph graph;

    this(Module m){
        this.graph = new ModuleDepGraph(m);
    }

    auto hash_ptr(const TemplateInstance ti){ // Benchmark this
        import core.stdc.tgmath: log2;
        auto tv = cast(void*)ti;
        const size_t shift = cast(size_t)log2(1.0+tv.sizeof);
        return cast(size_t)(tv) >> shift;
    }

    override void visit(TemplateInstance ti)
    {
        graph.add(ti);

        // now explore dependencies:
        if(ti.tinst !is null && ti.tinst != ti){ // is enclosed by another template
            graph.add(ti.tinst);
            graph.link(ti.tinst, ti);
        }
    }
}

auto write(Module _mod, ModuleDepGraph.Node[] nodes){

    class Tree{
        const(char)* name;
        const(char)* parent;
        Tree[] children;

        this(const(char)* name, const(char)* parent){
            this.name = name;
            this.parent = parent;
            this.children = [];
        }
        JSONValue toJson(){
            import std.string: fromStringz;
            import std.json;
            // auto j = JSONValue.object();
            auto j = JSONValue();
            j["name"] = JSONValue(name.fromStringz);
            j["parent"] = JSONValue(parent.fromStringz);
            j.object["children"] = children.map!(c => c.toJson()).array;
            return j;
        }
    }

    auto mod = _mod.toPrettyChars();

    Tree[TemplateInstance] mem; // memorize visited nodes
    foreach(n; nodes){
        write_traces(n.root);
        auto name = n.root.toPrettyChars();
        Tree root = new Tree(name, mod);
        foreach(c; n.children){
            auto child_tree = mem[c];
            assert(child_tree.parent == mod);

            child_tree.parent = root.name; // update parent
            root.children ~= child_tree; // append child to root
        }

        mem[n.root] = root; // key: TemplateInstance, value: root tree
    }

    auto roots = mem.values.filter!(tree => tree.parent == mod).array;

    char[64] fname = ""; strcat(fname.ptr, mod); strcat(fname.ptr, ".templates");
    auto root = new Tree(mod, null);
    root.children = roots;
    auto fp = fopen(fname.ptr, "w");
    fprintf(fp, "%s", root.toJson().toString.toStringz);
    fclose(fp);
}

void buildDepGraph(ref Modules modules) {
    foreach(ref m; modules){
        scope vis = new TempGraphVisitor(m);
        m.accept(vis);
        auto ts = vis.graph.topologicalSort();
        write(m, ts);
    }
}

/*
 * https://github.com/yazd/backtrace-d/blob/master/source/backtrace/backtrace.d
 */
version(linux) {
  // allow only linux platform
} else {
  pragma(msg, "backtrace only works in a Linux environment");
}

version(linux):

import std.stdio;
import core.sys.linux.execinfo;

private enum maxBacktraceSize = 32;
extern (C) void* thread_stackBottom();

struct Trace{
    size_t[maxBacktraceSize] u;
    alias u this;
}

Trace getBacktrace() {
    auto bt = getBacktraceImpl();
    Trace t;
    foreach(const i, const b; bt){
        t[i] = cast(size_t) b;
    }
    return t;
}

version(DigitalMars) {
  void*[] getBacktraceImpl() {
    enum CALL_INST_LENGTH = 1; // I don't know the size of the call instruction
                               // and whether it is always 5. I picked 1 instead
                               // because it is enough to get the backtrace
                               // to point at the call instruction
    void*[maxBacktraceSize] buffer;

    static void** getBasePtr() {
      version(D_InlineAsm_X86) {
        asm { naked; mov EAX, EBP; ret; }
      } else version(D_InlineAsm_X86_64) {
        asm { naked; mov RAX, RBP; ret; }
      } else return null;
    }

    auto stackTop = getBasePtr();
    auto stackBottom = cast(void**) thread_stackBottom();
    void* dummy;
    uint traceSize = 0;

    if (stackTop && &dummy < stackTop && stackTop < stackBottom) {
      auto stackPtr = stackTop;

      for (traceSize = 0; stackTop <= stackPtr && stackPtr < stackBottom && traceSize < buffer.length; ) {
        buffer[traceSize++] = (*(stackPtr + 1)) - CALL_INST_LENGTH;
        stackPtr = cast(void**) *stackPtr;
      }
    }

    return buffer[0 .. traceSize].dup;
  }
} else {
  void*[] getBacktraceImpl() {
    void*[maxBacktraceSize] buffer;
    auto size = backtrace(buffer.ptr, buffer.length);
    return buffer[0 .. size].dup;
  }
}


auto write_traces(TemplateInstance ti){
    import std.array: appender;
    import std.format: formattedWrite;

    auto writer = appender!string();
    enum fmt = "%ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul %ul\n";
    foreach(bt; ti.tracing.bt){
        size_t[32] t = bt.u;
        writer.formattedWrite!fmt(t[0], t[1], t[2], t[2], t[4], t[5], t[6], t[7],
                                  t[8], t[9], t[10], t[11], t[12], t[13], t[14], t[15],
                                  t[16], t[17], t[18], t[19], t[20], t[21], t[22], t[23],
                                  t[24], t[25], t[26], t[27], t[28], t[29], t[30], t[31]);
    }

    char[64] fname = ""; strcat(fname.ptr, ti.toPrettyChars); strcat(fname.ptr, ".trace");
    auto fp = fopen(ti.toPrettyChars, "w");
    fprintf(fp, "%s", writer.data.toStringz);
    fclose(fp);
}
