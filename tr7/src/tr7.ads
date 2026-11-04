--  Root of the verified core.
--
--  Every unit below Tr7 is SPARK_Mode => On and proved with GNATprove at
--  level 4 with --checks-as-errors (see docs/verification.md).
--
--  Runtime checks are a build property, never a source policy: the project
--  selects them with the TR7_CHECKS scenario (-gnata when "on", -gnatp when
--  "off"), so the same sources build a checked test binary and an unchecked
--  benchmark binary.  See docs/findings.md for why benchmarking with checks
--  enabled gives meaningless numbers.

package Tr7 is

end Tr7;
