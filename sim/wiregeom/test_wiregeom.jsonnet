local wc = import "wirecell.jsonnet";

// user picks based on "tracklist" external
local tracklist = std.extVar("tracklist");
local output = std.extVar("output");

local params = import "uboone_params.jsonnet";
local basics = import "basics.jsonnet";
local ionodes = import "ionodes.jsonnet";
local sim = import "simnodes.jsonnet";
local tracklists = import "tracklists.jsonnet";

local utils = basics.utils();
local anodes = basics.anodes(params);
local savers = ionodes.numpy(params, output);
local kine = sim.kine(params, tracklists[tracklist]);
local noise = sim.noise(params,anodes);
local signal = sim.signal(params,anodes);
local sink = sim.sink(params,anodes);


local edges = kine.edges + [
    {
        tail: kine.output,
        head: {node: wc.tn(savers.depo)},
    },
    {
        tail: {node: wc.tn(savers.depo)},
        head: signal.input,
    }
] +signal.edges + [
    {
        tail: signal.output,
        head: noise.input,
    }
] +noise.edges + [
    {
        tail: noise.output,
        head: {node: wc.tn(sink.digitizer)},
    },
    {
        tail: { node: wc.tn(sink.digitizer) },
        head: { node: wc.tn(savers.frame) },
    },
    {                   // terminate the stream
        tail: { node: wc.tn(savers.frame) },
        head: { node: wc.tn(sink.sink) },
    },
];


// Here the nodes are joined into a graph for execution by the main
// app object.  
local app = {
    type: "Pgrapher",
    data: {
        edges: edges,
    }
};
local extra = [savers.depo, savers.frame, sink.digitizer, sink.sink, app];

utils.cfgseq + anodes.cfgseq + kine.cfgseq + noise.cfgseq + signal.cfgseq + extra

