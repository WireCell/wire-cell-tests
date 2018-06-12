local wc = import "wirecell.jsonnet";

{
    numpy(params, npzfile)::
    local base_saver = {
        data: params.daq {
            filename: npzfile,
            frame_tags: [""],       // untagged.
            scale: if params.sim.digitize then 1.0 else wc.uV,
        }
    };
    local depo_saver = base_saver { type: "NumpyDepoSaver" };
    local frame_saver = base_saver { type: "NumpyFrameSaver" };

    // Here we do not return input/edges/output/cfgseq because user
    // may insert only one or the other or both (or none).
    {                           
        depo: depo_saver,
        frame: frame_saver,
    },
}

