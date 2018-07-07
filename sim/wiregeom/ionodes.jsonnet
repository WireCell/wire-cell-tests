local wc = import "wirecell.jsonnet";
local g = import "pgraph.jsonnet";

function(params, npzfile)
{
    local base_saver = {
        data: params.daq {
            filename: npzfile,
            frame_tags: [""],       // untagged.
            scale: if params.sim.digitize then 1.0 else wc.uV,
        }
    },
    depos: g.pnode(base_saver { type: "NumpyDepoSaver" }, nin=1, nout=1),
    frames: g.pnode(base_saver { type: "NumpyFrameSaver" }, nin=1, nout=1),
}

