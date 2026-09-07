import Foundation
import Darwin
import AMSMB2
func inUse() -> UInt64 {var s=malloc_statistics_t();malloc_zone_statistics(nil,&s);return UInt64(s.size_in_use)}
func require(_ condition:Bool,_ message:String) {if !condition {fputs("FAIL: \(message)\n",stderr);exit(1)}}
let port=CommandLine.arguments[1]
Task {
 do {
  let baseline=inUse()
  for cycle in 1...3 {
   let client=SMB2Manager(url:URL(string:"smb://127.0.0.1:\(port)")!,credential:URLCredential(user:"probe",password:"probe",persistence:.none))!
   try await client.connectShare(name:"fixture")
   for _ in 1...40 {
    let data=try await client.contents(atPath:"data.bin",range:UInt64(0)..<UInt64(4194304))
    require(data==Data(repeating:42,count:4194304),"full data")
   }
   let tail=try await client.contents(atPath:"data.bin",range:UInt64(4194288)..<UInt64(4194320))
   require(tail==Data(repeating:42,count:16),"short tail read")
   let eof=try await client.contents(atPath:"data.bin",range:UInt64(4194304)..<UInt64(4194320))
   require(eof.isEmpty,"EOF")
   var failed=false
   do {_ = try await client.contents(atPath:"absent.bin",range:UInt64(0)..<UInt64(16))} catch {failed=true}
   require(failed,"missing file error")
   let again=try await client.contents(atPath:"data.bin",range:UInt64(0)..<UInt64(16))
   require(again==Data(repeating:42,count:16),"recovery after error")
   try await client.disconnectShare(gracefully:true)
   let memory=inUse()
   print("cycle \(cycle): size_in_use=\(memory) baseline=\(baseline)");fflush(stdout)
   require(memory < baseline + 16*1024*1024,"read responses accumulated after disconnect")
  }
  print("SMB memory / full data / short read / EOF / error recovery PASS");exit(0)
 }catch{print(error);exit(1)}
}
dispatchMain()
