--  Datum reader.
--
--  The reader is a bounded recursive-descent parser over a string.  It never
--  allocates anything except heap data, and it reports a precise status so the
--  REPL can distinguish "end of input" from a syntax error.

with Tr7.Heap; use Tr7.Heap;
with Tr7.Values; use Tr7.Values;

with Tr7.Config;

package Tr7.Reader with
   SPARK_Mode => On
is

   type Read_Status is (Read_Ok, Read_End, Read_Error);

   --  Parse a decimal token.  Is_Float says whether the text has the shape
   --  of a number at all (a false answer sends the token on to become a
   --  symbol); Ok says whether that number is representable.
   procedure Parse_Float
     (Text     : String;
      Is_Float : out Boolean;
      X        : out Long_Float;
      Ok       : out Boolean)
     with
       Pre  => Text'First >= 1
         and then Text'Last < Natural'Last
         and then Text'Length <= Tr7.Config.Max_Text;

   procedure Read_Datum
     (H      : in out Heap_Type;
      Source : String;
      Pos    : in out Natural;
      Result : out Value;
      Status : out Read_Status)
     with
       Pre  => H.Ready
         and then Source'First = 1
         and then Source'Last <= Natural'Last - 2
         and then Pos <= Source'Length,
       Post => H.Ready and then Pos <= Source'Length;

end Tr7.Reader;
