-- |
-- Tests for the @.opx@ reader.
--
-- The XML here is written out in full rather than built by a helper, because
-- every test in this file is about a detail of how ORIPA's serialiser lays a
-- crease out, and a helper that produced the layout would be asserting against
-- itself.
--
-- Two of them are the reason the reader is not four lines long. Properties are
-- read by /name/, so the same crease written in two different property orders
-- gives the same segment; and a property equal to zero is not written at all,
-- so an absent one is a zero rather than a missing field.
module Senbazuru.Import.OpxSpec (spec) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient)
import Senbazuru.Fold.Types (Assignment (..), Frame (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Import.Cp qualified as Cp
import Senbazuru.Import.Opx
import Senbazuru.Import.Segments
import Test.Hspec

-- | Wrap some @OriLineProxy@ objects in the modern dialect's scaffolding,
-- @mainVersion@ and all, so that every test also checks that the wrapper is
-- skipped rather than read as a crease.
modern :: Text -> Text
modern lines' =
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
  \<java version=\"21.0.2\" class=\"java.beans.XMLDecoder\">\n\
  \ <object class=\"oripa.DataSet\" id=\"DataSet0\">\n\
  \  <void class=\"oripa.DataSet\" method=\"getField\">\n\
  \   <string>lines</string>\n\
  \   <void method=\"set\">\n\
  \    <object idref=\"DataSet0\"/>\n\
  \    <array class=\"oripa.OriLineProxy\" length=\"1\">\n\
  \     <void index=\"0\">\n"
    <> lines'
    <> "     </void>\n\
       \    </array>\n\
       \   </void>\n\
       \  </void>\n\
       \  <void property=\"mainVersion\">\n\
       \   <int>1</int>\n\
       \  </void>\n\
       \  <void property=\"paperSize\">\n\
       \   <double>400.0</double>\n\
       \  </void>\n\
       \ </object>\n\
       \</java>\n"

-- | A crease with its properties in the order ORIPA writes them: @type@, then
-- both @x@s, then both @y@s, because @XMLEncoder@ sorts a bean's properties by
-- name.
inOripaOrder :: Text
inOripaOrder =
  "      <object class=\"oripa.OriLineProxy\">\n\
  \       <void property=\"type\">\n\
  \        <int>3</int>\n\
  \       </void>\n\
  \       <void property=\"x0\">\n\
  \        <double>10.0</double>\n\
  \       </void>\n\
  \       <void property=\"x1\">\n\
  \        <double>30.0</double>\n\
  \       </void>\n\
  \       <void property=\"y0\">\n\
  \        <double>20.0</double>\n\
  \       </void>\n\
  \       <void property=\"y1\">\n\
  \        <double>40.0</double>\n\
  \       </void>\n\
  \      </object>\n"

-- | The same crease, its properties shuffled into point order.
inPointOrder :: Text
inPointOrder =
  "      <object class=\"oripa.OriLineProxy\">\n\
  \       <void property=\"x0\">\n\
  \        <double>10.0</double>\n\
  \       </void>\n\
  \       <void property=\"y0\">\n\
  \        <double>20.0</double>\n\
  \       </void>\n\
  \       <void property=\"x1\">\n\
  \        <double>30.0</double>\n\
  \       </void>\n\
  \       <void property=\"y1\">\n\
  \        <double>40.0</double>\n\
  \       </void>\n\
  \       <void property=\"type\">\n\
  \        <int>3</int>\n\
  \       </void>\n\
  \      </object>\n"

-- | Read a fixture as text, the way 'Senbazuru.Fold.Load.decodeFile' does.
fixture :: FilePath -> IO Text
fixture path = decodeUtf8Lenient <$> BS.readFile path

spec :: Spec
spec = do
  describe "assignmentForCode" $ do
    it "reads ORIPA's four codes" $ do
      assignmentForCode 0 `shouldBe` Just Flat
      assignmentForCode 1 `shouldBe` Just Border
      assignmentForCode 2 `shouldBe` Just Mountain
      assignmentForCode 3 `shouldBe` Just Valley

    it "puts auxiliary at 0, where a .cp file puts it at 4" $ do
      -- The one place the two formats disagree, and the reason each reader
      -- carries its own table instead of sharing one.
      assignmentForCode 4 `shouldBe` Nothing
      assignmentForCode (-1) `shouldBe` Nothing

  describe "parseOpx" $ do
    it "reads a crease's endpoints by property name, not by position" $
      -- ORIPA writes x0, x1, y0, y1. A reader that took the four numbers in
      -- the order it met them would put x1 into y0 and draw (10, 30)-(20, 40),
      -- which is a plausible-looking crease and the wrong one.
      fmap (map (\s -> (segStart s, segEnd s))) (parseOpx (modern inOripaOrder))
        `shouldBe` Right [(V2 10 (-20), V2 30 (-40))]

    it "reads the same crease however the properties are ordered" $
      parseOpx (modern inPointOrder) `shouldBe` parseOpx (modern inOripaOrder)

    it "reads a property that is not there as zero" $ do
      -- XMLEncoder omits any value a freshly built bean already has, and a
      -- fresh OriLineProxy is all zeroes, so this crease runs from the origin.
      -- Its type is missing too, which means 0: an auxiliary line.
      let crease =
            "      <object class=\"oripa.OriLineProxy\">\n\
            \       <void property=\"x1\">\n\
            \        <double>30.0</double>\n\
            \       </void>\n\
            \      </object>\n"
      fmap (map (\s -> (segStart s, segEnd s, segAssignment s))) (parseOpx (modern crease))
        `shouldBe` Right [(V2 0 0, V2 30 0, Flat)]

    it "reads the dialect ORIPA wrote before Java hid the field" $ do
      -- The 2005-era wrapper: <void property="lines"> straight round the
      -- array, with none of the getField ceremony. Same creases.
      let old =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
            \<java version=\"1.5.0_06\" class=\"java.beans.XMLDecoder\">\n\
            \ <object class=\"oripa.DataSet\">\n\
            \  <void property=\"lines\">\n\
            \   <array class=\"oripa.OriLineProxy\" length=\"1\">\n\
            \    <void index=\"0\">\n"
              <> inOripaOrder
              <> "    </void>\n\
                 \   </array>\n\
                 \  </void>\n\
                 \ </object>\n\
                 \</java>\n"
      fmap (map (\s -> (segStart s, segEnd s))) (parseOpx old)
        `shouldBe` Right [(V2 10 (-20), V2 30 (-40))]

    it "does not mistake the document's own properties for creases" $
      -- paperSize and mainVersion are <void property="..."> too, and they sit
      -- outside every OriLineProxy. One crease in, one crease out.
      fmap length (parseOpx (modern inOripaOrder)) `shouldBe` Right 1

    it "finds nothing in a document that is not an .opx at all" $
      (parseOpx "<html><body>not this</body></html>" >>= frameFromSegments)
        `shouldBe` Left EmptyPattern

    it "refuses a value that is not a number, naming the line of the XML" $ do
      let crease =
            "      <object class=\"oripa.OriLineProxy\">\n\
            \       <void property=\"x0\">\n\
            \        <double>fifty</double>\n\
            \       </void>\n\
            \      </object>\n"
      parseOpx (modern crease) `shouldBe` Left (MalformedLine 12 "not a number: fifty")

    it "refuses an unknown type code, naming the line and the code" $ do
      let crease =
            "      <object class=\"oripa.OriLineProxy\">\n\
            \       <void property=\"type\">\n\
            \        <int>9</int>\n\
            \       </void>\n\
            \      </object>\n"
      -- Line 12 is the <int>9</int>; line 10 is the enclosing <object>. The
      -- line to name is the one a person would go to in order to change it.
      parseOpx (modern crease) `shouldBe` Left (UnknownLineType 12 9)

    it "skips a property whose value is not a number" $ do
      -- ORIPA's bean is five numbers today. A sixth field of some other type,
      -- in some later version, must not stop the creases being readable -- and
      -- before this was handled it stopped the whole file, not just the field.
      let crease =
            "      <object class=\"oripa.OriLineProxy\">\n\
            \       <void property=\"label\">\n\
            \        <string>a name</string>\n\
            \       </void>\n\
            \       <void property=\"type\">\n\
            \        <int>2</int>\n\
            \       </void>\n\
            \       <void property=\"x1\">\n\
            \        <double>30.0</double>\n\
            \       </void>\n\
            \      </object>\n"
      fmap (map (\s -> (segStart s, segEnd s, segAssignment s))) (parseOpx (modern crease))
        `shouldBe` Right [(V2 0 0, V2 30 0, Mountain)]

    it "steps over an object nested inside a property" $ do
      -- The walk is over a flat stream of tags, so the </object> that closes
      -- the nested one looks exactly like the one that closes the crease.
      -- Miss that and everything after it is silently not read: the type and
      -- the coordinates here would both be lost, and the crease would come out
      -- as a point at the origin rather than as an error.
      let crease =
            "      <object class=\"oripa.OriLineProxy\">\n\
            \       <void property=\"meta\">\n\
            \        <object class=\"oripa.Meta\">\n\
            \         <void property=\"weight\">\n\
            \          <int>7</int>\n\
            \         </void>\n\
            \        </object>\n\
            \       </void>\n\
            \       <void property=\"type\">\n\
            \        <int>2</int>\n\
            \       </void>\n\
            \       <void property=\"x1\">\n\
            \        <double>30.0</double>\n\
            \       </void>\n\
            \      </object>\n"
      fmap (map (\s -> (segStart s, segEnd s, segAssignment s))) (parseOpx (modern crease))
        `shouldBe` Right [(V2 0 0, V2 30 0, Mountain)]

    it "refuses an object that is never closed" $
      parseOpx "<object class=\"oripa.OriLineProxy\">\n <void property=\"type\">\n"
        `shouldBe` Left (MalformedLine 1 "an <object> that is never closed")

  describe "the quarter fold" $
    it "reads the same twelve creases the .cp file has" $ do
      -- The same drawing in the other format, written as ORIPA would write
      -- it -- properties sorted by name, zeroes left out entirely. Compared
      -- against the .cp rather than against a list typed out here, because
      -- the point is that the two formats say the same thing.
      opx <- fixture "test/fixtures/quarter-fold.opx"
      cp <- fixture "test/fixtures/quarter-fold.cp"
      case (parseOpx opx >>= frameFromSegments, Cp.parseCp cp >>= frameFromSegments) of
        (Right fromOpx, Right fromCp) -> do
          length (edgesVertices fromOpx) `shouldBe` 12
          verticesCoords fromOpx `shouldBe` verticesCoords fromCp
          edgesVertices fromOpx `shouldBe` edgesVertices fromCp
          edgesAssignment fromOpx `shouldBe` edgesAssignment fromCp
        (a, b) -> expectationFailure (show a <> " / " <> show b)
