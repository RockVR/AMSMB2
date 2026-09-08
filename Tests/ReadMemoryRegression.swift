import Foundation
import Darwin
import AMSMB2
func inUse() -> UInt64 {var s=malloc_statistics_t();malloc_zone_statistics(nil,&s);return UInt64(s.size_in_use)}
func require(_ condition:Bool,_ message:String) {if !condition {fputs("FAIL: \(message)\n",stderr);exit(1)}}
func expected(_ offset:Int,_ count:Int) -> Data { Data((offset..<(offset+count)).map { UInt8($0 % 256) }) }
let port=CommandLine.arguments[1]
Task {
 do {
  let baseline=inUse()
  for cycle in 1...3 {
   let client=SMB2Manager(url:URL(string:"smb://127.0.0.1:\(port)")!,credential:URLCredential(user:"probe",password:"probe",persistence:.none))!
   print("cycle \(cycle): connecting");fflush(stdout)
   try await client.connectShare(name:"fixture")
   print("connected; reading");fflush(stdout)
   for _ in 1...40 {
    let data=try await client.contents(atPath:"data.bin",range:UInt64(0)..<UInt64(4194304))
    require(data==expected(0,4194304),"full data")
   }
   let tail=try await client.contents(atPath:"data.bin",range:UInt64(4194288)..<UInt64(4194320))
   require(tail==expected(4194288,16),"short tail read")
   let eof=try await client.contents(atPath:"data.bin",range:UInt64(4194304)..<UInt64(4194320))
   require(eof.isEmpty,"EOF")
   var failed=false
   do {_ = try await client.contents(atPath:"absent.bin",range:UInt64(0)..<UInt64(16))} catch {failed=true}
   require(failed,"missing file error")
   let again=try await client.contents(atPath:"data.bin",range:UInt64(0)..<UInt64(16))
   require(again==expected(0,16),"recovery after error")
   for i in 0..<48 {
    let offset = (i % 2 == 0 ? i * 7919 : 4190000 - i * 7919)
    let data = try await client.contents(atPath:"data.bin",range:UInt64(offset)..<UInt64(offset+257))
    require(data == expected(offset,257),"alternating random-access data")
   }
   print("disconnecting");fflush(stdout)
   try await client.disconnectShare(gracefully:true)
   let memory=inUse()
   print("cycle \(cycle): size_in_use=\(memory) baseline=\(baseline)");fflush(stdout)
   require(memory < baseline + 16*1024*1024,"read responses accumulated after disconnect")
  }
  let guest=SMB2Manager(url:URL(string:"smb://127.0.0.1:\(port)")!,credential:URLCredential(user:"guest",password:"",persistence:.none))!
  guest.timeout = 5
  print("guest connecting");fflush(stdout)
  try await guest.connectShare(name:"fixture")
  print("guest reading");fflush(stdout)
  let guestData=try await guest.contents(atPath:"data.bin",range:UInt64(13)..<UInt64(270))
  require(guestData == expected(13,257),"unsigned guest read")
  try await guest.disconnectShare(gracefully:true)
  print("SMB memory / random access / guest / short read / EOF / error recovery PASS");exit(0)
 }catch{print(error);exit(1)}
}
dispatchMain()
