# Constellation's features as an Obsidian plugin over the same Vault format

The standalone Constellation app rebuilt an Obsidian-like editor, search, Tags pane, graph and renames in order to add a
few things specific to the domain: Calls and Uses, staleness, the Archive, and the agent files. We moved those few
things into an Obsidian plugin and left everything else to Obsidian. The plugin reads exactly the Vault format the app
defines, so neither side can change the format alone, and one Vault opens in both. As a result, Call, Uses and
Containment edges are no longer drawn in the graph (Obsidian draws one kind of edge), and archiving became an explicit
command instead of happening on tick, because Obsidian's undo cannot span the two files the move touches.
