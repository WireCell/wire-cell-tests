// modified on Brett's for uBooNE simulation
// To be fixed: +/-0.15 for even/odd wirens field response shift
// To be fixed: geometry issue for uBooNE. shift of u, v planed needed
// To be updated using new unit system by Brett.

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
#include "TTree.h"
#include "TH1F.h"
#include "TClonesArray.h"

#include <iostream>
#include <string>
#include <cmath>
#include <memory>
#include <time.h>

using namespace WireCell;
using namespace std;

#define TIME

int main(int argc, char *argv[])
{
    PluginManager& pm = PluginManager::instance();
    pm.add("WireCellGen");
    {
        auto rngcfg = Factory::lookup<IConfigurable>("Random");
        auto cfg = rngcfg->default_configuration();
        rngcfg->configure(cfg);
    }

#ifdef TIME
    clock_t t1;
    t1 = clock();
#endif
    // Need to set WIRECELL_PATH, see env.sh
    TFile* rootfile;
    string response_file = "ub-10-wnormed.json.bz2";
    if (argc < 4) {
        std::cerr << "usage: test_depos2waves <cfg.json> <field-file.json.[.bz2]> <output.root>" 
            << std::endl;
        std::cerr << "Not Wire Cell field response input file given, will try to use:\n"
            << response_file << std::endl;
        if (argc<3) {
            std::cerr << "usage: test_depos2waves <cfg.json> <output.root>" << std::endl;
            return 1;
        }
        rootfile = TFile::Open(argv[2], "recreate");
    }
    else {
        response_file = argv[2];
        rootfile = TFile::Open(argv[3], "recreate");
    }
    
    // Warning: this is abusing the configuration by being so
    // monolithic.  It's just for this test!  Do not emulate!
    auto cfg = Persist::load(argv[1]);
    auto fr = Response::Schema::load(response_file.c_str());
 
    // [HY] Simulation output celltree
    // Sim Tree
    TTree *Sim = new TTree("Sim","Wire-cell toolkit simulation output");
    // branches init (not complete, used in prototype app)
    Int_t runNo = 0;
    Int_t subRunNo = 0;
    Int_t eventNo = 0;
    Int_t raw_nChannel = 8256;
    std::vector<int> *raw_channelId = new std::vector<int>;
    TClonesArray *sim_wf = new TClonesArray("TH1F");
    TH1::AddDirectory(kFALSE);
    // branches set
    Sim->Branch("runNo", &runNo, "runNo/I");
    Sim->Branch("subRunNo", &subRunNo, "subRunNo/I");
    Sim->Branch("eventNo", &eventNo, "eventNo/I");
    Sim->Branch("raw_nChannel", &raw_nChannel, "raw_nChannel/I");

    Sim->Branch("raw_channelId", &raw_channelId);

    // element index consistent with ChannelId >>TO BE SOLVED: what is raw_wf strored in celltree?
    Sim->Branch("raw_wf", &sim_wf, 256000, 0);
    //sim_wf->BypassStreamer();
    //sim_wf->Clear();
    // for sim_wf fill one by one adjacent, otherwise a crash of memory
    int sim_wf_ind = 0; 

    // number of wires for uvw, configuration in .json
    //Int_t nwire[3]={2400, 2400, 3456};

    // Y plane field response normalized to 1.6e-19C, preamp response output is 14 with input 1. Nothing else supposed in the scale. 
    double scale_factor = 1.0; 
    TH1F* hbaseline[3];
    Int_t baseline_val[3] = {1800, 1800, 500};
    for(Int_t i=0; i<3; i++)
    {
        hbaseline[i] = new TH1F(Form("baseline%d", i), "", 9600, 0, 9600);
        for(Int_t j=0; j<9600; j++)
        {
            hbaseline[i]->SetBinContent(j+1, baseline_val[i]);
        }
    }
    // end

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

    std::cerr << "Readout_time: "<< readout_time/units::ms << " ms \n"
              << "Field response origin: " << field_origin/units::mm << "mm \n"
              << "drift speed: " << drift_speed/units::mm/units::us << " mm/us \n"
              << "Tbins center 10: "<< tbins.center(10) << "Shaping: "<<shaping << std::endl;
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
#ifdef TIME
    t1 = clock()-t1;
    std::cout<<"Input time consumption: "<<t1<<" ticks"<<" ("<<((float)t1)/CLOCKS_PER_SEC<<" seconds)"<<std::endl;
    clock_t t2;
    t2 = clock();
#endif
    
    // Do a dumb, simple uniform drift.
    // In a real app this would be a WCT "node".
    // Warning: for DL/DT we assume goofy, implicit units!
    const double DL = get(cfg, "DL", 6.4374) * units::centimeter2/units::second;
    const double DT = get(cfg, "DT", 10.729) * units::centimeter2/units::second;
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
        const double sigmaT = sqrt(2*DT*dt/units::centimeter2)*units::centimeter;

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
            //bindiff.add(depo, 50*units::ns, 0.04*units::mm);
        //    std::cerr<<depo->extent_long()/drift_speed<<" "<<depo->extent_tran()<<endl;
        }

        PlaneImpactResponse pir(fr, iplane, tbins, gain, shaping);

        Gen::ImpactZipper zipper(pir, bindiff);

        std::map<int, Waveform::realseq_t> frame;
        int minwire=-1, maxwire=-1;
        int mintick=-1, maxtick=-1;

        for (int iwire=0; iwire<nwires; ++iwire) {
            auto wave = zipper.waveform(iwire);
           
            // [HY] wf fill
            // for wf fill, 9600 ticks and 12-bit ADC
            Int_t index = iwire + iplane*2400;
            //std::cout<<"Plane: "<<iplane<<"  Wire: "<<iwire<<std::endl;
            //std::cout<<"Wire Index: "<<index<<std::endl;
            raw_channelId->push_back(index);    
            TH1F *htemp = new ( (*sim_wf)[sim_wf_ind] ) TH1F("", "",  9600, 0, 9600);
            
//            htemp->SetMinimum(0);
//            htemp->SetMaximum(4096);
            for (Int_t i=1; i<=9600; i++)
            {
                htemp->SetBinContent(i, wave[i-1]);
            } 
            htemp->Scale(-1.0*scale_factor);
            //htemp->Add(hbaseline[iplane]);
            // Due to odd wires bug
            sim_wf_ind++;
            /* for odd wire input with actual even wire output
            if(iwire == nwires - 1)
            {
                Int_t index2 = index + 1;
                raw_channelId->push_back(index2);    
                TH1F *htemp2 = new ( (*sim_wf)[sim_wf_ind] ) TH1F("", "",  9600, 0, 9600);
                for (Int_t i=1; i<=9600; i++)
                {
                    htemp2->SetBinContent(i, wave[i-1]);
                } 
                htemp2->Scale(-1.0*scale_factor);
                sim_wf_ind++;
            }
            */
            //std::cout<<"Filled: "<<sim_wf_ind<<std::endl;
            // end, next step will cut off zero region
  
            auto mm = Waveform::edge(wave);
            if ((unsigned)mm.first == wave.size()) { // all zero
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
                  nwbins, minwire, maxwire+1);
        
        // [HY] Test TClonesArray output
        TH2F histClone(Form("plane%dclone", iplane),
                       Form("Plane %d clone", iplane),
                       ntbins, mintick, maxtick, 
                       nwbins, minwire, maxwire+1);


        for (auto it : frame) {
            const int iwire = it.first;
            const auto& wave = it.second;
            
            // [HY] Clone TClonesArray
            std::vector<int>::iterator itw;
            itw = find(raw_channelId->begin(), raw_channelId->end(), iwire+iplane*2400);
            TH1F* h = dynamic_cast<TH1F*>(sim_wf->At(std::distance(raw_channelId->begin(), itw)));  
            for (int itick = mintick; itick < maxtick; ++itick) {
                hist.Fill(tbins.center(itick)/units::us, iwire, wave[itick]);

                histClone.Fill(itick, iwire, h->GetBinContent(itick+1));
            }
        }

        hist.Write();
        histClone.Write();

        hist.Delete();
        histClone.Delete();
    }
#ifdef TIME
    t2 = clock()-t2;
    std::cout<<"Sim time consumption: "<<t2<<" ticks"<<" ("<<((float)t2)/CLOCKS_PER_SEC<<" seconds)"<<std::endl;
    clock_t t3;
    t3 = clock();
#endif

    Sim->Fill();
    //Sim tree save
    // Event directory
    TDirectory *event = rootfile->mkdir("Event");
    event->cd();
    Sim->Write();

    rootfile->Close();
    sim_wf->Delete();
    delete raw_channelId;

#ifdef TIME
    t3 = clock()-t3;
    std::cout<<"Output time consumption: "<<t3<<" ticks"<<" ("<<((float)t3)/CLOCKS_PER_SEC<<" seconds)"<<std::endl;
#endif

    return 0;
}
    
