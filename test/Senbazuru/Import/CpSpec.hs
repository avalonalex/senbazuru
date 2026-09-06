-- |
-- Tests for the @.cp@ reader.
--
-- Two kinds. The type-code table is walked directly, because it is the part of
-- the format that is a decision rather than a syntax, and reading a fixture and
-- hoping the counts come out right would not say which code meant what.
-- Everything else is example tests on text, with the awkward cases taken from
-- files real editors wrote rather than invented: the scientific notation Java
-- reaches for below a thousandth, the negative zero a reflection leaves
-- behind, and the trailing newline every writer ends with.
--
-- The one file read here is Oriedita's own bird base, which is the format's
-- worst case for the endpoint merging in "Senbazuru.Import.Segments": 52
-- endpoints, 22 distinct spellings, 13 vertices.
module Senbazuru.Import.CpSpec (spec) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient)
import Senbazuru.Fold.Types (Assignment (..), Frame (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Import.Cp
import Senbazuru.Import.Segments
import Senbazuru.Origami.FlatFold (checkFrame, defaultTolerance, reportChecked, reportViolations)
import Test.Hspec

-- | Read a fixture as text, the way 'Senbazuru.Fold.Load.decodeFile' does.
fixture :: FilePath -> IO Text
fixture path = decodeUtf8Lenient <$> BS.readFile path

spec :: Spec
spec = do
  describe "assignmentForCode" $ do
    it "reads the four codes the format has always had" $ do
      assignmentForCode 1 `shouldBe` Just Border
      assignmentForCode 2 `shouldBe` Just Mountain
      assignmentForCode 3 `shouldBe` Just Valley
      assignmentForCode 4 `shouldBe` Just Flat

    it "reads Oriedita's further auxiliary colours as flat too" $
      -- Codes 5 to 11 are its LineColor enumeration -- orange, magenta,
      -- green, yellow, purple, other, grey -- plus one. All construction
      -- lines, all F.
      map assignmentForCode [5 .. 11] `shouldBe` replicate 7 (Just Flat)

    it "refuses a code no writer produces" $ do
      -- 0 in particular: it would be LineColor's NONE, the marker for a line
      -- that is not there, and a file with one is using some other numbering.
      assignmentForCode 0 `shouldBe` Nothing
      assignmentForCode 12 `shouldBe` Nothing
      assignmentForCode (-1) `shouldBe` Nothing

  describe "parseCp" $ do
    it "reads a line as a type and two points" $
      parseCp "3 1.0 2.0 3.0 4.0"
        `shouldBe` Right
          [ Segment
              { segLine = 1,
                segStart = V2 1 (-2),
                segEnd = V2 3 (-4),
                segAssignment = Valley
              }
          ]

    it "reads y downwards, as the editor that wrote the file drew it" $
      -- The whole of the flip, in one assertion: a crease ten units *below*
      -- the origin on Oriedita's screen is ten units below it on the paper,
      -- which in a y-up model space is y = -10.
      fmap (map segEnd) (parseCp "2 0.0 0.0 0.0 10.0")
        `shouldBe` Right [V2 0 (-10)]

    it "reads the scientific notation Java writes small numbers in" $
      -- Straight out of bird-base.cp, where a rotation left a corner of the
      -- paper 2.4e-14 off the axis it belongs on.
      fmap (map segStart) (parseCp "1 2.4492935982947067E-14 -200.0 200.0 -200.0")
        `shouldBe` Right [V2 2.4492935982947067e-14 200.0]

    it "reads the negative zero a reflection leaves behind" $
      -- Not a claim about the sign: (-0.0) == 0.0, so no shouldBe here could
      -- see one. The claim is that the reader accepts the spelling at all,
      -- which bird-base.cp needs it to twice.
      fmap (map segEnd) (parseCp "2 1.0 1.0 -0.0 -0.0")
        `shouldBe` Right [V2 0 0]

    it "skips blank lines but still counts them" $ do
      -- The trailing newline every writer leaves is a blank line, so a reader
      -- that refused one would refuse every real file. Line numbers keep
      -- counting through them, because that is what an editor shows.
      let text = "1 0.0 0.0 1.0 0.0\n\n2 1.0 0.0 1.0 1.0\n"
      fmap (map segLine) (parseCp text) `shouldBe` Right [1, 3]

    it "reads a file saved on Windows" $
      fmap (map segAssignment) (parseCp "1 0.0 0.0 1.0 0.0\r\n2 1.0 0.0 1.0 1.0\r\n")
        `shouldBe` Right [Border, Mountain]

    it "refuses a line without five fields, naming it" $
      parseCp "1 0.0 0.0 1.0 0.0\n2 1.0 0.0 1.0\n"
        `shouldBe` Left (MalformedLine 2 "expected a type and four coordinates, found 4 fields")

    it "refuses a coordinate that is not a number, naming which one" $
      parseCp "1 0.0 0.0 1.0 0.0\n2 1.0 x 1.0 1.0\n"
        `shouldBe` Left (MalformedLine 2 "y1 is not a number: x")

    it "refuses a coordinate with something stuck on the end" $
      -- Reader combinators stop at the first thing they do not understand and
      -- hand back the rest, so a reader that ignored the remainder would read
      -- "1.0mm" as 1.0.
      parseCp "1 0.0 0.0 1.0mm 0.0"
        `shouldBe` Left (MalformedLine 1 "x2 is not a number: 1.0mm")

    it "refuses an unknown type code, naming the line and the code" $
      parseCp "1 0.0 0.0 1.0 0.0\n99 1.0 0.0 1.0 1.0\n"
        `shouldBe` Left (UnknownLineType 2 99)

  describe "the bird base" $ do
    it "merges 22 spellings of its endpoints into 13 vertices" $ do
      -- Six creases meet at the centre and the file spells that one point
      -- three ways, none of them 0. Without the merging this frame would have
      -- 22 vertices and the six creases at the centre would not meet.
      text <- fixture "test/fixtures/bird-base.cp"
      case parseCp text >>= frameFromSegments of
        Left err -> expectationFailure (show err)
        Right frame -> do
          length (verticesCoords frame) `shouldBe` 13
          length (edgesVertices frame) `shouldBe` 26

    it "reads each line's own type code, in order" $ do
      -- Eight border segments -- the square's four sides, each split at its
      -- midpoint -- twelve mountains and six valleys, interleaved as the file
      -- happens to list them. A reader that sorted, or that read the codes off
      -- by one, would not produce this sequence.
      text <- fixture "test/fixtures/bird-base.cp"
      fmap (map segAssignment) (parseCp text)
        `shouldBe` Right (map toAssignment "BBBBVVVBBVBBVMMMMMMMMMMVMM")

    it "folds flat at every one of its interior vertices" $ do
      -- The acceptance test for the whole reader, and it is here because it
      -- is really a test of the endpoint merging: six creases meet at the
      -- centre of a bird base, and unless the three spellings of that point
      -- became one vertex there is no such vertex to check. Maekawa and
      -- Kawasaki are not what is on trial.
      text <- fixture "test/fixtures/bird-base.cp"
      case parseCp text >>= frameFromSegments of
        Left err -> expectationFailure (show err)
        Right frame -> case checkFrame defaultTolerance frame of
          Left err -> expectationFailure (show err)
          Right report -> do
            length (reportChecked report) `shouldBe` 5
            reportViolations report `shouldBe` []
  where
    toAssignment = \case
      'B' -> Border
      'M' -> Mountain
      _ -> Valley
