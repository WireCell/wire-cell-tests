// base detector parametrs.  Together, these match no real detector.
// The data structure is organized and named to have synergy with
// configuration objects for the simulation nodes defined later.
local wc = import "wirecell.jsonnet";
{
    lar : {
        DL :  7.2 * wc.cm2/wc.s,
        DT : 12.0 * wc.cm2/wc.s,
        lifetime : 8*wc.ms,
        drift_speed : 1.6*wc.mm/wc.us, // 500 V/cm
        density: 1.389*wc.g/wc.centimeter3,
        ar39activity: 1*wc.Bq/wc.kg,
    },
    detector : {
        // Relative extent for active region of LAr box.  
        // (x,y,z) = (drift distance, active height, active width)
        extent: [1*wc.m,1*wc.m,1*wc.m],
        // the center MUST be expressed in the same coordinate system
        // as the wire endpoints given in the files.wires entry below.
        // Default here is that the extent is centered on the origin
        // of the wire coordinate system.
        center: [0,0,0],
        drift_time: self.extent[0]/self.lar.drift_speed,
        drift_volume: self.extent[0]*self.extent[1]*self.extent[2],
        drift_mass: $.lar.density * self.drift_volume,
    },
    daq : {
        readout_time: 5*wc.ms,
        nreadouts: 1,
        start_time: 0.0*wc.s,
        stop_time: self.start_time + self.nreadouts*self.readout_time,
        tick: 0.5*wc.us,        // digitization time period
        sample_period: 0.5*wc.us, // sample time for any spectral data - usually same as tick
        first_frame_number: 100,
        ticks_per_readout: self.readout_time/self.tick,
    },
    adc : {
        gain: 1.0,
        baselines: [900*wc.millivolt,900*wc.millivolt,200*wc.millivolt],
        resolution: 12,
        fullscale: [0*wc.volt, 2.0*wc.volt],
    },
    elec : {
        gain : 14.0*wc.mV/wc.fC,
        shaping : 2.0*wc.us,
        postgain: 1.2,
    },
    sim : {
        fluctuate: true,
        digitize: true,
        noise: true,
    },
    files : {                   // each detector MUST fill these in.
        wires: null,
        fields: null,
        noise: null,
    }
}
