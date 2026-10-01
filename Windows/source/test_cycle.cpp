#include "cycle.hpp"
#include <cassert>
#include <vector>
#include <iostream>
struct Mock {
 uint64_t clock=0,stopAt=UINT64_MAX; unsigned failOn=0,calls=0; uint32_t latency=0; bool off=false;
 std::vector<bool> states; std::vector<uint32_t> waits;
 uint64_t now(){return clock;} bool cancelled(){return clock>=stopAt;}
 void wait(uint32_t n){waits.push_back(n);clock=std::min(clock+n,stopAt);}
 uint32_t change(bool state){++calls;clock+=latency;if(calls==failOn)return 5;states.push_back(state);off=state;return 0;}
 void progress(const cycle::Result&,bool){}
};
int main(){
 {Mock m;auto r=cycle::run({30,70,3,0},m);assert(r.completed==3&&r.switches==6&&!r.error&&m.clock==300&&!m.off);}
 {Mock m;m.stopAt=45;auto r=cycle::run({100,100,0,0},m);assert(r.switches==1&&r.completed==0&&m.clock==45&&m.off);}
 {Mock m;m.stopAt=150;auto r=cycle::run({100,100,0,0},m);assert(r.switches==2&&r.completed==1&&m.clock==150&&!m.off);}
 {Mock m;auto r=cycle::run({100,100,0,45},m);assert(r.switches==1&&m.clock==45);}
 {Mock m;auto r=cycle::run({100,100,0,200},m);assert(r.completed==1&&r.switches==2&&m.clock==200);}
 {Mock m;m.failOn=1;auto r=cycle::run({10,10,5,0},m);assert(r.error==5&&!r.switches&&m.waits.empty());}
 {Mock m;m.failOn=2;auto r=cycle::run({10,10,5,0},m);assert(r.error==5&&r.switches==1&&r.completed==0&&m.off);}
 {Mock m;m.stopAt=0;auto r=cycle::run({10,10,0,0},m);assert(r.switches==0&&m.calls==0);}
 {Mock m;m.stopAt=200000;auto r=cycle::run({10,10,0,0},m);assert(r.completed==10000&&r.switches==20000);}
 {Mock m;m.latency=90;auto r=cycle::run({10,10,0,50},m);assert(r.switches==1&&m.waits.empty()&&m.clock==90);}
 {Mock m;m.latency=5;auto r=cycle::run({10,10,2,0},m);assert(r.completed==2&&m.clock==60);}
 {Mock m;auto r=cycle::run({100,100,100,250},m);assert(r.completed==1&&r.switches==3&&m.clock==250);}
 {Mock m;m.stopAt=1250;auto r=cycle::manual(m);assert(r.switches==1&&r.completed==0&&m.calls==1&&m.off&&m.clock==1250);}
 {Mock m;m.stopAt=0;auto r=cycle::manual(m);assert(r.switches==0&&m.calls==0);}
 {Mock m;m.failOn=1;auto r=cycle::manual(m);assert(r.error==5&&r.switches==0&&m.waits.empty());}
 {Mock m;m.stopAt=100000;auto r=cycle::manual(m);assert(r.switches==1&&m.states.size()==1&&m.off);}
 {Mock m;m.latency=100;m.stopAt=50;auto r=cycle::manual(m);assert(r.switches==1&&m.waits.empty());}
 {Mock m;int picks=0;auto r=cycle::runWithPicker({10,30,3,0,20,50},m,[&](uint32_t lo,uint32_t hi){++picks;return picks%2?lo:hi;});assert(r.completed==3&&picks==6&&m.clock==180);for(size_t i=0;i<m.waits.size();++i)assert(m.waits[i]==(i%2?50:10));}
 {Mock m;auto r=cycle::runWithPicker({10,20,2,25,100,100},m,[](uint32_t,uint32_t hi){return hi;});assert(r.switches==1&&m.clock==25&&m.waits[0]==25);}
 {Mock m;m.stopAt=15;auto r=cycle::runWithPicker({10,30,0,0,100,100},m,[](uint32_t,uint32_t hi){return hi;});assert(r.switches==1&&m.clock==15);}
 {Mock m;auto r=cycle::runWithPicker({50,30,2,0,20,100},m,[](uint32_t lo,uint32_t){return lo;});assert(r.error==87&&m.calls==0);}
 {Mock m;int picks=0;auto r=cycle::runWithPicker({10,20,2,0,10,20},m,[&](uint32_t lo,uint32_t){++picks;return lo;});assert(!r.error&&r.completed==2&&picks==0&&m.clock==60);}
 {Mock m;auto r=cycle::runWithPicker({10,20,2,0,100,100},m,[](uint32_t,uint32_t){return 999u;});assert(r.error==87&&r.switches==1&&m.waits.empty());}
 {Mock m;std::mt19937 rng(12345);auto r=cycle::runWithPicker({10,80,1000,0,40,130},m,[&](uint32_t lo,uint32_t hi){return std::uniform_int_distribution<uint32_t>(lo,hi)(rng);});assert(!r.error&&r.completed==1000);bool varied=false;for(size_t i=0;i<m.waits.size();++i){auto n=m.waits[i];assert(i%2?(n>=80&&n<=130):(n>=10&&n<=40));if(i>1&&n!=m.waits[i-2])varied=true;}assert(varied);}
 {Mock m;m.failOn=1;int picks=0;auto r=cycle::runWithPicker({10,20,2,0,100,100},m,[&](uint32_t lo,uint32_t){++picks;return lo;});assert(r.error==5&&picks==0);}
 std::cout<<"PASS: 25 automatic/manual, randomized range, cancellation and failure scenarios\n";
}
