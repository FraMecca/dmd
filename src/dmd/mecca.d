module dmd.mecca;

import core.stdc.stdio;
import std.algorithm.iteration: map, each, filter;
import std.array: array;
import std.json;

import dmd.visitor;
import dmd.dmodule;
import dmd.arraytypes;
import dmd.dtemplate;
import dmd.permissivevisitor;
import dmd.dsymbol;

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
    import core.stdc.string;

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
    import std.string: toStringz;
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
