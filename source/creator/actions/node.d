/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
module creator.actions.node;
import creator.core.actionstack;
import creator.actions;
import creator;
import inochi2d;
import std.format;
import i18n;
import std.exception;

/**
    An action that happens when a node is changed
*/
class NodeMoveAction : Action {
public:

    /**
        Descriptive name
    */
    string descrName;
    
    /**
        Which index in to the parent the nodes should be placed
    */
    size_t parentOffset;

    /**
        Previous parent of node
    */
    Node[uint] prevParents;
    size_t[uint] prevOffsets;

    /**
        Nodes that was moved
    */
    Node[] nodes;

    /**
        New parent of node
    */
    Node newParent;

    /**
        The original transform of the node
    */
    Transform originalTransform;

    /**
        The new transform of the node
    */
    Transform newTransform;

    /**
        Creates a new node change action
    */
    this(Node[] nodes, Node new_, size_t pOffset = 0) {
        this.newParent = new_;
        this.nodes = nodes;
        this.parentOffset = pOffset;

        // Enforce reparenting rules
        foreach(sn; nodes) enforce(sn.canReparent(new_), _("%s can not be reparented in to %s due to a circular dependency.").format(sn.name, new_.name));
        
        // Reparent
        foreach(ref sn; nodes) {
            
            // Store ref to prev parent
            if (sn.parent) {
                prevParents[sn.uuid] = sn.parent;
                prevOffsets[sn.uuid] = sn.getIndexInParent();
            }

            // Set relative position
            sn.setRelativeTo(new_);
            sn.parent = new_;
            sn.insertInto(new_, pOffset);
        }
        incActivePuppet().rescanNodes();
    
        // Set visual name
        if (nodes.length == 1) descrName = nodes[0].name;
        else descrName = _("nodes");
    }

    /**
        Rollback
    */
    void rollback() {
        foreach(ref sn; nodes) {
            sn.setRelativeTo(prevParents[sn.uuid]);
            sn.insertInto(prevParents[sn.uuid], prevOffsets[sn.uuid]);
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Redo
    */
    void redo() {
        foreach(sn; nodes) {
            sn.setRelativeTo(newParent);
            sn.insertInto(newParent, parentOffset);
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Describe the action
    */
    string describe() {
        if (prevParents.length == 0) return _("Created %s").format(descrName);
        if (newParent is null) return _("Deleted %s").format(descrName);
        return _("Moved %s to %s").format(descrName, newParent.name);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        if (prevParents.length == 0) return _("Created %s").format(descrName);
        if (nodes.length == 1 && prevParents.length == 1) return  _("Moved %s from %s").format(descrName, prevParents[nodes[0].uuid].name);
        return _("Moved %s from origin").format(descrName);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    bool merge(Action other) { return false; }
    bool canMerge(Action other) { return false; }
}

/**
    Action for whether a node was activated or deactivated
*/
class NodeActiveAction : Action {
public:
    Node self;
    bool newState;

    /**
        Rollback
    */
    void rollback() {
        self.enabled = !newState;
    }

    /**
        Redo
    */
    void redo() {
        self.enabled = newState;
    }

    /**
        Describe the action
    */
    string describe() {
        return "%s %s".format(newState ? _("Enabled") : _("Disabled"), self.name);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        return _("%s was %s").format(self.name, !newState ? _("Enabled") : _("Disabled"));
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    bool merge(Action other) { return false; }
    bool canMerge(Action other) { return false; }
}

/**
    Moves multiple children with history
*/
void incMoveChildrenWithHistory(Node[] n, Node to, size_t offset) {
    // Push action to stack
    incActionPush(new NodeMoveAction(
        n,
        to,
        offset
    ));
}

/**
    Moves child with history
*/
void incMoveChildWithHistory(Node n, Node to, size_t offset) {
    incMoveChildrenWithHistory([n], to, offset);
}

/**
    Adds child with history
*/
void incAddChildWithHistory(Node n, Node to, string name=null) {
    if (to is null) to = incActivePuppet().root;

    // Push action to stack
    incActionPush(new NodeMoveAction(
        [n],
        to
    ));

    n.insertInto(to, Node.OFFSET_START);
    if (name is null) n.name = _("Unnamed ")~_(n.typeId());
    else n.name = name;
    incActivePuppet().rescanNodes();
}

/**
    Deletes child with history
*/
void incDeleteChildWithHistory(Node n) {
    // Push action to stack
    incActionPush(new NodeMoveAction(
        [n],
        null
    ));

    n.parent = null;
    incActivePuppet().rescanNodes();
}

/**
    Node value changed action
*/
class NodeValueChangeAction(TNode, T) : Action if (is(TNode : Node)) {
public:
    alias TSelf = typeof(this);
    TNode node;
    T oldValue;
    T newValue;
    T* valuePtr;
    string name;

    this(string name, TNode node, T oldValue, T newValue, T* valuePtr) {
        this.name = name;
        this.node = node;
        this.oldValue = oldValue;
        this.newValue = newValue;
        this.valuePtr = valuePtr;
    }

    /**
        Rollback
    */
    void rollback() {
        *valuePtr = oldValue;
    }

    /**
        Redo
    */
    void redo() {
        *valuePtr = newValue;
    }

    /**
        Describe the action
    */
    string describe() {
        return _("%s->%s changed to %s").format(node.name, name, newValue);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        return _("%s->%s changed from %s").format(node.name, name, oldValue);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return name;
    }
    
    /**
        Merge
    */
    bool merge(Action other) {
        if (this.canMerge(other)) {
            this.newValue = (cast(TSelf)other).newValue;
            return true;
        }
        return false;
    }

    /**
        Gets whether this node can merge with an other
    */
    bool canMerge(Action other) {
        TSelf otherChange = cast(TSelf) other;
        return (otherChange !is null && otherChange.getName() == this.getName());
    }
}