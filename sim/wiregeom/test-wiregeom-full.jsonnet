local wc = import "wirecell.jsonnet";
local g = import "pgraph.jsonnet";

// user picks based on "tracklist" external
local tracklist = std.extVar("tracklist");
local output = std.extVar("output");


local uboone_params = import "uboone_params.jsonnet";
local params = uboone_params {
    sim: super.sim {
        fluctuate: false,       // override to give clean signal for debugging
    }
};
local common = import "common.jsonnet";
local tools = common(params);


local ionodes = import "ionodes.jsonnet";
local io = ionodes(params, output);

local simnodes = import "simnodes.jsonnet";
local tracklists = import "tracklists.jsonnet";
local sim = simnodes(params, tools, tracklists[tracklist]);

local pipeline_elements = [
    sim.tracks_and_blips,
    io.depos,
    sim.drifter,
    sim.multi_ductor,
    sim.plus_noise,
    sim.digitizer,
    io.frames,
    sim.frame_sink,
];
local graph = g.pipeline(pipeline_elements);

// Here the nodes are joined into a graph for execution by the main
// app object.  
local app = {
    type: "Pgrapher",
    data: {
        edges: graph.edges,
    }
};
[tools.cmdline] + graph.uses + [app]
