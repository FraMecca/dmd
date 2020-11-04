module dmd.mecca;

import core.stdc.stdio;
import std.algorithm.iteration: map, each, filter;

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

    import std.array: array;
    const roots = mem.values.filter!(tree => tree.parent == mod).array;

    char[64] fname = ""; strcat(fname.ptr, mod); strcat(fname.ptr, ".templates");
    auto fp = fopen(fname.ptr, "w");
    fprintf(fp, `{"name":"%s", "parent":null, "children":[`, mod);

    void writeJsonString(const(Tree) tree){
        fprintf(fp, `{"name":"%s", "parent":"%s", "children":[`, tree.name, tree.parent);
        if(tree.children.length) foreach(child; tree.children[0..$-1]){
            writeJsonString(child);
            fprintf(fp, ",");
        }
        if(tree.children.length > 1) writeJsonString(tree.children[$-1]); // avoid final comma
        fprintf(fp, `]}`);
    }

    if(roots.length) foreach(r; roots[0..$-1]){
        writeJsonString(r);
        fprintf(fp, `,`);
    }
    if(roots.length > 0) writeJsonString(roots[$-1]);
    fprintf(fp, `]}`);
}

void buildDepGraph(ref Modules modules) {
    foreach(ref m; modules){
        scope vis = new TempGraphVisitor(m);
        m.accept(vis);
        auto ts = vis.graph.topologicalSort();
        write(m, ts);
    }
}
