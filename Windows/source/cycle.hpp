#pragma once
#include <cstdint>
#include <algorithm>
#include <random>
namespace cycle {
struct Settings { uint32_t offMs=500,onMs=500; uint64_t count=10,limitMs=0; uint32_t offMaxMs=0,onMaxMs=0; };
struct Result { uint64_t completed=0, switches=0; uint32_t error=0; };
template<class Backend,class Picker> Result runWithPicker(const Settings& s,Backend& b,Picker pick) {
 Result r;
 const uint32_t offMax=s.offMaxMs?s.offMaxMs:s.offMs,onMax=s.onMaxMs?s.onMaxMs:s.onMs;
 if(!s.offMs||!s.onMs||offMax<s.offMs||onMax<s.onMs){r.error=87;return r;}
 const auto start=b.now();
 auto done=[&]{return b.cancelled()||(s.limitMs&&b.now()-start>=s.limitMs);};
 auto pause=[&](uint32_t low,uint32_t high){
  if(done())return;
  uint64_t n=low==high?low:pick(low,high);
  if(n<low||n>high){r.error=87;return;}
  if(s.limitMs){auto elapsed=b.now()-start;if(elapsed>=s.limitMs)return;n=std::min(n,s.limitMs-elapsed);}
  b.wait(static_cast<uint32_t>(n));
 };
 while(!done()&&(!s.count||r.completed<s.count)){
  r.error=b.change(true);if(r.error)break;
  ++r.switches;b.progress(r,true);pause(s.offMs,offMax);if(r.error||done())break;
  r.error=b.change(false);if(r.error)break;
  ++r.switches;++r.completed;b.progress(r,false);pause(s.onMs,onMax);if(r.error)break;
 }
 return r;
}
template<class Backend> Result run(const Settings& s,Backend& b){
 if(!s.offMaxMs&&!s.onMaxMs)return runWithPicker(s,b,[](uint32_t low,uint32_t){return low;});
 std::mt19937 rng(std::random_device{}());
 return runWithPicker(s,b,[&](uint32_t low,uint32_t high){return std::uniform_int_distribution<uint32_t>(low,high)(rng);});
}
template<class Backend> Result manual(Backend& b){
 Result r;if(b.cancelled())return r;r.error=b.change(true);if(r.error)return r;
 r.switches=1;b.progress(r,true);while(!b.cancelled())b.wait(250);return r;
}
}
