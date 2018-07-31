#include "WireCellUtil/Configuration.h"
#include "WireCellUtil/Persist.h"
#include "WireCellUtil/Response.h"
#include "WireCellUtil/Units.h"
#include "WireCellUtil/Point.h"
#include "WireCellUtil/Testing.h"
#include "WireCellUtil/Pimpos.h"
#include "WireCellUtil/PlaneImpactResponse.h"
#include "WireCellIface/SimpleDepo.h"
#include "WireCellGen/BinnedDiffusion.h"
#include "WireCellGen/ImpactZipper.h"

#include "WireCellUtil/PluginManager.h"
#include "WireCellUtil/NamedFactory.h"
#include "WireCellIface/IRandom.h"
#include "WireCellIface/IConfigurable.h"

#include "TFile.h"
#include "TH2F.h"

#include <iostream>
#include <string>
#include <cmath>
#include <memory>

using namespace WireCell;

int main(int argc, char *argv[])
{
    PluginManager& pm = PluginManager::instance();
    pm.add("WireCellGen");
    {
        auto rngcfg = Factory::lookup<IConfigurable>("Random");
        auto cfg = rngcfg->default_configuration();
        rngcfg->configure(cfg);
    }


    if (argc<4) {
        std::cerr << "usage: test_depos2waves <cfg.json> <garfield.json[.bz2]> <output.root>" << std::endl;
        return 1;
    }

    // Warning: this is abusing the configuration by being so
    // monolithic.  It's just for this test!  Do not emulate!
    auto cfg = Persist::load(argv[1]);
    auto fr = Response::Schema::load(argv[2]);
    TFile* rootfile = TFile::Open(argv[3], "recreate");

    // Angle is positive and same for U and V.
    const double angle = 60*units::degree;

    // Wire direction
    std::vector<Vector> uvw_wire{Vector(0,  cos(angle),  sin(angle)), // points Y>0, Z>0
                                 Vector(0,  cos(angle), -sin(angle)), // points Y>0, Z<0
                                 Vector(0, 1, 0)};

    // Pitch direction points generally in +Z direction
    std::vector<Vector> uvw_pitch{Vector(0, -sin(angle),  cos(angle)),
                                  Vector(0,  sin(angle),  cos(angle)),
                                  Vector(0, 0, 1)};
    
    for (int ind=0; ind<3; ++ind) {
        Vector cross = uvw_wire[ind].cross(uvw_pitch[ind]);
        const Vector drift(1.0,0.0,0.0);
        const Vector diff = drift-cross;
        Assert(std::abs(diff.magnitude()) < 0.0001);
    }

    // Origin where drift and diffusion meets field response.
    Point field_origin(fr.origin, 0, 0);

    // load in configuration parameters
    const double t0 = get(cfg, "t0", 0.0*units::ns);
    const double readout_time = get(cfg, "readout", 5*units::ms);
    const double tick = get(cfg, "tick", 0.5*units::us);
    const int nticks = readout_time/tick;
    const double drift_speed = get(cfg,"speed",1.0*units::mm/units::us);
    Binning tbins(nticks, t0, t0+readout_time);
    const double gain = get(cfg, "gain", 14.0);
    const double shaping  = get(cfg, "shaping", 2.0*units::us);

    std::cerr << "Field response origin: " << field_origin/units::mm << "mm "
              << "drift speed: " << drift_speed / (units::mm/units::us) << " mm/us\n";

    // load in configured depos
    WireCell::IDepo::vector orig_depos;
    for (auto hit : cfg["depos"]) {
        auto depo = std::make_shared<SimpleDepo>(
            get(hit,"t",0.0*units::ns),
            Point(get(hit, "x", 0.0),
                  get(hit, "y", 0.0),
                  get(hit, "z", 0.0)),
            get(hit,"q",1000.0));
        orig_depos.push_back(depo);
    }


    // Do a dumb, simple uniform drift.
    // In a real app this would be a WCT "node".
    // Warning: for DL/DT we assume goofy, implicit units!
    const double DL = get(cfg, "DL", 5.3) * units::centimeter2/units::second;
    const double DT = get(cfg, "DT", 12.8) * units::centimeter2/units::second;
    WireCell::IDepo::vector drifted_depos;
    for (auto depo : orig_depos) {
        Point here = depo->pos();
        const double dt = (here.x() - field_origin.x())/drift_speed;
        const double now = depo->time() + dt;
        std::cerr << here/units::m << " m" << std::endl;
        here.x(field_origin.x());
        std::cerr << dt/units::ms << " " << now/units::ms << " " << depo->time()/units::ms << std::endl;

        const double tmpcm2 = 2*DL*dt/units::centimeter2;
        //const double sigmaL = sqrt(tmpcm2)*units::centimeter / drift_speed;
        const double sigmaL = sqrt(tmpcm2)*units::centimeter;
        const double sigmaT = sqrt(2*DT*dt/units::centimeter2)*units::centimeter2;

        auto drifted = std::make_shared<SimpleDepo>(now, here, depo->charge(), depo, sigmaL, sigmaT);
        drifted_depos.push_back(drifted);

        std::cerr << "   Depo: " << depo->pos()/units::mm << " mm @ " << depo->time()/units::ms << " ms\n";
        std::cerr << "drifted: " << drifted->pos()/units::mm << " mm @ " << drifted->time()/units::ms << " s\n";
    }

    const bool fluctuate = convert<bool>(cfg["fluctuate"]);
    IRandom::pointer rng = nullptr;
    if (fluctuate) {
        rng = Factory::lookup<IRandom>("Random");
    }
    // final drift sim
    for (int iplane=0; iplane<3; ++iplane) {
        auto& pr = fr.planes[iplane];
        const double wire_pitch = pr.pitch;
        const double impact_pitch = pr.paths[1].pitchpos - pr.paths[0].pitchpos;
        const int nregion_bins = round(wire_pitch/impact_pitch);
        const int nwires = convert<int>(cfg["nwires"][iplane]);
        const double halfwireextent = wire_pitch * 0.5 * (nwires - 1);
        const double ndiffision_sigma = convert<double>(cfg["nsigma"]);

        Pimpos pimpos(nwires, -halfwireextent, halfwireextent,
                      uvw_wire[iplane], uvw_pitch[iplane],
                      field_origin, nregion_bins);

        std::cerr << "Plane " << iplane << ": nwires=" << nwires
                  << " half extent:" << halfwireextent
                  << " nimpacts/region: " << nregion_bins << std::endl;
        
        Gen::BinnedDiffusion bindiff(pimpos, tbins, ndiffision_sigma, rng);
        for (auto depo : drifted_depos) {
            bindiff.add(depo, depo->extent_long() / drift_speed, depo->extent_tran());
        }

        PlaneImpactResponse pir(fr, iplane, tbins, gain, shaping);

        Gen::ImpactZipper zipper(pir, bindiff);

        std::map<int, Waveform::realseq_t> frame;
        int minwire=-1, maxwire=-1;
        int mintick=-1, maxtick=-1;

        for (int iwire=0; iwire<nwires; ++iwire) {
            auto wave = zipper.waveform(iwire);

            auto mm = Waveform::edge(wave);
            if (mm.first == (int)wave.size()) { // all zero
                continue;
            }

            if (minwire<0) {    // first time
                minwire = maxwire = iwire;
                mintick = mm.first;
                maxtick = mm.second;
            }
            else {
                minwire = std::min(minwire, iwire);
                maxwire = std::max(maxwire, iwire);
                mintick = std::min(mintick, mm.first);
                maxtick = std::max(maxtick, mm.second);
            }

            frame[iwire] = wave;

            /// fixme, about here we need to start thinking about
            /// output format.  also noise and digitizing.
        }

        const int ntbins = maxtick - mintick; // no +1 because maxtick is 1 past 
        const double tmin = tbins.edge(mintick);
        const double tmax = tbins.edge(maxtick);
        const int nwbins = maxwire - minwire + 1;

        std::cerr
            << "plane:" << iplane
            << " tbins:" << ntbins << " [" << tmin/units::us << "," << tmax/units::us << "]"
            << " wbins:" << nwbins << " [" << minwire << "," << maxwire << "]\n";

        TH2F hist(Form("plane%d", iplane),
                  Form("Plane %d", iplane),
                  ntbins, tmin/units::us, tmax/units::us,
                  nwbins, minwire, maxwire);
        for (auto it : frame) {
            const int iwire = it.first;
            const auto& wave = it.second;
            for (int itick = mintick; itick < maxtick; ++itick) {
                hist.Fill(tbins.center(itick)/units::us, iwire, wave[itick]);
            }
        }
        hist.Write();
    }

    rootfile->Close();

    return 0;
}
    
