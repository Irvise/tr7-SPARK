--  C ABI layer: the second half of the trusted boundary, where C pointers and
--  the tr7.h entry points live.  The verified core never sees either, so this
--  unit is deliberately outside SPARK.

package Tr7_C with SPARK_Mode => Off is

end Tr7_C;
