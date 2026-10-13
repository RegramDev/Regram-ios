import Foundation
@main struct Tests {
 static func main() {
  var value = RGDatacenterStatistics()
  assert(value.average == nil && value.minimum == nil && value.variation == nil)
  value.connectionMilliseconds = 2000
  value.samples = [100, 200, 300]
  assert(value.average == 200 && value.minimum == 100)
  assert(abs(value.variation! - sqrt(20000.0 / 3.0)) < 0.001)
  value.failures = 2
  assert(value.average == 200, "Failures must not fabricate zero-latency responses")
  assert(value.connectionMilliseconds == 2000, "Warmup must not enter request statistics")
  print("DC statistics passed: warmup exclusion, failed-request handling, minimum/average and variation.")
 }
}
