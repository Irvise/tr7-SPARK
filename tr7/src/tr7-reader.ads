--  Datum reader.
--
--  The reader is a bounded recursive-descent parser over a string.  It never
--  allocates anything except heap data, and it reports a precise status so the
--  REPL can distinguish "end of input" from a syntax error.

with Tr7.Config;
with Tr7.Heap; use Tr7.Heap;
with Tr7.Values; use Tr7.Values;

package Tr7.Reader with
   SPARK_Mode => On
is

   type Read_Status is (Read_Ok, Read_End, Read_Error);

   procedure Intern
     (H      : in out Heap_Type;
      Name   : String;
      Result : out Value;
      Ok     : out Boolean)
     with
       Pre  => H.Ready
         and then Name'First >= 1
         and then Name'Length <= Tr7.Config.Max_Text,
       Post => (if Ok then Is_Handle (Result));

   procedure Read_Datum
     (H      : in out Heap_Type;
      Source : String;
      Pos    : in out Natural;
      Result : out Value;
      Status : out Read_Status)
     with
       Pre  => H.Ready
         and then Source'First = 1
         and then Pos <= Source'Length,
       Post => Pos <= Source'Length;

end Tr7.Reader;
