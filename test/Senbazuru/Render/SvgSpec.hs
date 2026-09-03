-- |
-- Tests for the SVG backend.
--
-- Two layers are tested separately on purpose. 'formatNumber' and 'escapeXml'
-- get ordinary example tests, because their contract is a list of specific
-- cases. The document as a whole gets a golden test, because its contract is
-- "these exact bytes" and enumerating that by hand would be worse than useless.
module Senbazuru.Render.SvgSpec (spec) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (renderFoldError)
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry
import Senbazuru.Render.CreasePattern (creasePattern)
import Senbazuru.Render.Svg
import Test.Golden (goldenText)
import Test.Hspec

-- | Render a fixture the same way the CLI would, with a fixed page so the
-- output does not depend on defaults changing.
renderFixture :: FilePath -> IO Text
renderFixture path = do
  bytes <- BS.readFile path
  f <- either (fail . ("decode failed: " <>)) pure (decodeFoldFile bytes)
  d <- case creasePattern defaultTheme (keyFrame f) of
    Left err -> fail ("render failed: " <> T.unpack (renderFoldError err))
    Right d -> pure d
  pure (renderSvg testPage d)

-- | Deliberately not 'defaultPage': a golden file should not churn because
-- someone retunes the default margin.
testPage :: Page
testPage =
  defaultPage
    { pageWidth = 200,
      pageHeight = 200,
      pageMargin = 10,
      pageTitle = Just "fixture"
    }

spec :: Spec
spec = do
  describe "formatNumber" $ do
    it "drops trailing zeros" $
      formatNumber 1.5 `shouldBe` "1.5"

    it "drops the decimal point when nothing follows it" $
      formatNumber 42 `shouldBe` "42"

    it "never uses scientific notation" $
      -- show (0.0001 :: Double) is "1.0e-4", which would make the output format
      -- depend on the magnitude of the number.
      formatNumber 0.0001 `shouldNotSatisfy` T.isInfixOf "e"

    it "rounds to three decimals" $
      formatNumber (1 / 3) `shouldBe` "0.333"

    it "normalises negative zero, which a y-flip can produce" $ do
      -- -0.0 == 0.0 is True, so this difference is invisible to tests that
      -- compare Doubles, but very visible in a golden file.
      formatNumber (-0.0) `shouldBe` "0"
      formatNumber (negate 0.0001) `shouldBe` "0"

    it "collapses non-finite values rather than writing NaN into an attribute" $ do
      formatNumber (0 / 0) `shouldBe` "0"
      formatNumber (1 / 0) `shouldBe` "0"

  describe "escapeXml" $ do
    it "escapes the characters that would break the document" $
      escapeXml "a & b < c > d \" e ' f"
        `shouldBe` "a &amp; b &lt; c &gt; d &quot; e &apos; f"

    it "leaves ordinary text alone" $
      escapeXml "Yoshizawa" `shouldBe` "Yoshizawa"

  describe "renderSvg" $ do
    let square =
          diagramWithExtent
            (Box (V2 0 0) (V2 1 1))
            [ Polyline (solid (Colour "#000000") 1) [V2 0 0, V2 1 0],
              Polyline (Stroke (Colour "#000000") 1 (Dash [4, 2])) [V2 0 0, V2 1 1]
            ]

    it "emits a viewBox matching the page size" $
      renderSvg testPage square `shouldSatisfy` T.isInfixOf "viewBox=\"0 0 200 200\""

    it "emits stroke-dasharray only for dashed strokes" $ do
      let out = renderSvg testPage square
      T.count "stroke-dasharray" out `shouldBe` 1
      out `shouldSatisfy` T.isInfixOf "stroke-dasharray=\"4 2\""

    it "flips the y axis, so model (0,0) is at the bottom of the page" $
      -- The content box is 10..190. Model y = 0 is the bottom of the extent, so
      -- it must land at page y = 190, not 10.
      renderSvg testPage square `shouldSatisfy` T.isInfixOf "M 10 190 L 190 190"

    it "skips a polyline with fewer than two points" $ do
      let dot =
            diagramWithExtent
              (Box (V2 0 0) (V2 1 1))
              [Polyline (solid (Colour "#000000") 1) [V2 0 0]]
      T.count "<path" (renderSvg testPage dot) `shouldBe` 0

    it "escapes the title, which comes from a user-supplied file" $ do
      let page = testPage {pageTitle = Just "Fish & <chips>"}
      renderSvg page square
        `shouldSatisfy` T.isInfixOf "<title>Fish &amp; &lt;chips&gt;</title>"

  describe "end-to-end golden output" $ do
    it "renders unit-square.fold exactly as recorded" $
      renderFixture "test/fixtures/unit-square.fold"
        >>= goldenText "test/golden/unit-square.svg"

    it "renders diagonal-cp.fold exactly as recorded" $
      renderFixture "test/fixtures/diagonal-cp.fold"
        >>= goldenText "test/golden/diagonal-cp.svg"
