#pragma once
#include <cstdint>
// Google Workspace networking documentation, verified 2026-10-01.
// https://knowledge.workspace.google.com/admin/meet/prepare-your-network-for-meet-meetings-and-live-streams
struct MeetRange {const wchar_t* address;uint8_t bits;bool ipv6;};
static constexpr MeetRange meetRanges[]={
 {L"74.125.250.0",24,false},{L"74.125.247.128",32,false},{L"142.250.82.0",24,false},
 {L"2001:4860:4864:5::",64,true},{L"2001:4860:4864:4:8000::",128,true},{L"2001:4860:4864:6::",64,true}
};
