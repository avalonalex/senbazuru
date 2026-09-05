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
import Senbazuru.Diagram.Layout (defaultGrid, gridOf)
import Senbazuru.Diagram.Style (Notation (..), arrowFor, defaultTheme)
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (renderFoldError)
import Senbazuru.Fold.Types (FoldFile (..), allFrames)
import Senbazuru.Geometry
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Step (motionsBetween)
import Senbazuru.Render.Camera (Basis, isometric, topDown)
import Senbazuru.Render.CreasePattern (creasePatternAuto, creasePatternFrom, withArrows)
import Senbazuru.Render.Svg
import Test.Golden (goldenText)
import Test.Hspec

-- | Render a fixture as a crease pattern, with a fixed page so the output does
-- not depend on defaults changing.
renderFixture :: FilePath -> IO Text
renderFixture = renderFixtureFrom CreasePatternNotation topDown

-- | Render a fixture in a given notation through a given viewing basis.
--
-- Both are spelled out rather than left to 'creasePatternAuto', which is what
-- the CLI uses. A golden file should pin what the renderer draws, and the
-- heuristics that choose the notation and the view have their own tests in
-- "Senbazuru.Render.CreasePatternSpec".
renderFixtureFrom :: Notation -> Basis -> FilePath -> IO Text
renderFixtureFrom notation basis path = do
  bytes <- BS.readFile path
  f <- either (fail . ("decode failed: " <>)) pure (decodeFoldFile bytes)
  d <- case creasePatternFrom defaultTheme notation basis (keyFrame f) of
    Left err -> fail ("render failed: " <> T.unpack (renderFoldError err))
    Right d -> pure d
  pure (renderSvg testPage d)

-- | Fold a crease-pattern fixture and render the result.
--
-- The whole pipeline in one line: decode, fold along the file's own angles,
-- draw what comes out. The folded frame goes through exactly the renderer a
-- file-supplied folded form does, which is the point — nothing downstream knows
-- these coordinates were computed.
renderFolded :: Basis -> FilePath -> IO Text
renderFolded basis path = do
  bytes <- BS.readFile path
  f <- either (fail . ("decode failed: " <>)) pure (decodeFoldFile bytes)
  folded <- either (fail . ("fold failed: " <>) . show) pure (foldFrame (keyFrame f))
  d <- case creasePatternFrom defaultTheme FoldedFormNotation basis folded of
    Left err -> fail ("render failed: " <> T.unpack (renderFoldError err))
    Right d -> pure d
  pure (renderSvg testPage d)

-- | One arrow across a square model of the given size, so that two sizes can be
-- compared for anything that ought not to depend on the model's scale.
arrowDiagram :: Double -> Diagram
arrowDiagram size =
  diagramWithExtent
    (Box (V2 0 0) (V2 size size))
    [ Arrow
        ( arrowFor
            defaultTheme
            (V2 (0.25 * size) (0.5 * size))
            (V2 (0.75 * size) (0.5 * size))
        )
    ]

-- | Render one frame of a sequence with the arrows for the step it begins.
renderStep :: Int -> FilePath -> IO Text
renderStep i path = do
  bytes <- BS.readFile path
  f <- either (fail . ("decode failed: " <>)) pure (decodeFoldFile bytes)
  let frames = allFrames f
  (thisStep, nextStep) <- case drop i frames of
    (a : b : _) -> pure (a, b)
    _ -> fail "fixture does not have two frames from there"
  motions <- either (fail . show) pure (motionsBetween thisStep nextStep)
  d <- case creasePatternFrom defaultTheme CreasePatternNotation topDown thisStep of
    Left err -> fail ("render failed: " <> T.unpack (renderFoldError err))
    Right d -> pure d
  pure (renderSvg testPage (withArrows defaultTheme topDown motions d))

-- | Every frame of a file, arrows and all, laid out as one page.
renderSteps :: FilePath -> IO Text
renderSteps path = do
  bytes <- BS.readFile path
  f <- either (fail . ("decode failed: " <>)) pure (decodeFoldFile bytes)
  let frames = allFrames f
  figures <- traverse (figure frames) (zip [0 ..] frames)
  case gridOf (defaultGrid (Colour "#1a1a1a")) figures of
    Nothing -> fail "nothing to lay out"
    Just d -> pure (renderSvg testPage {pageWidth = 400} d)
  where
    figure frames (i, fr) = do
      d <- case creasePatternAuto defaultTheme (Just topDown) fr of
        Left err -> fail ("render failed: " <> T.unpack (renderFoldError err))
        Right d -> pure d
      case drop (i + 1) frames of
        [] -> pure d
        (next : _) -> do
          ms <- either (fail . show) pure (motionsBetween fr next)
          pure (withArrows defaultTheme topDown ms d)

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

    it "fills a polygon and closes its path" $ do
      let tri =
            diagramWithExtent
              (Box (V2 0 0) (V2 1 1))
              [Polygon (Colour "#abcdef") [V2 0 0, V2 1 0, V2 0 1]]
          out = renderSvg testPage tri
      out `shouldSatisfy` T.isInfixOf "M 10 190 L 190 190 L 10 10 Z"
      out `shouldSatisfy` T.isInfixOf "fill=\"#abcdef\""
      -- No stroke on the path: the group sets fill="none" and leaves stroke at
      -- its initial "none", so a polygon that names only a fill is unstroked.
      -- The outline of a face comes from the crease edges that run along it.
      T.count "stroke=" out `shouldBe` 0

    it "draws an arrow as a curve and a solid head" $ do
      let out = renderSvg testPage (arrowDiagram 1)
      -- A quadratic Bezier, not a straight line: the mark means the paper turns
      -- through the air rather than sliding along the page.
      out `shouldSatisfy` T.isInfixOf " Q "
      -- Two paths: the stroked curve and the filled head.
      T.count "<path" out `shouldBe` 2
      T.count "fill=\"#1a1a1a\"" out `shouldBe` 1

    it "keeps the arrowhead the same size however big the model is" $ do
      -- The two-unit rule, in the one shape that needs both units at once. A
      -- head measured in model units would be a speck on a large sheet and
      -- would swallow a small one.
      let headOf = filter (T.isInfixOf "fill=") . T.lines . renderSvg testPage
      headOf (arrowDiagram 1) `shouldBe` headOf (arrowDiagram 400)

    it "shrinks the head rather than drawing the arrow backwards" $ do
      -- The head is a fixed size in page units, and a small flap on a large
      -- sheet can move less far than that. This arrow spans 7.36 page units and
      -- the theme's head is 11, so unclamped the curve would be pulled back past
      -- its own start and drawn in reverse underneath a head that swallowed it.
      --
      -- Pinned exactly, because the number that matters is easy to state: the
      -- curve starts at x = 200 and must end to the right of it. It ended at
      -- 197.5 before the head was clamped.
      let stubby =
            diagramWithExtent
              (Box (V2 0 0) (V2 1 1))
              [Arrow (arrowFor defaultTheme (V2 0.5 0.5) (V2 0.52 0.5))]
          out = renderSvg defaultPage stubby
      out `shouldSatisfy` T.isInfixOf "M 200 200 Q 203.68 198.16 204.069 198.354"
      T.count "<path" out `shouldBe` 2

    it "writes a label as text, escaped" $ do
      -- Emitted as <text> rather than as outlines, so the file stays small and
      -- the number stays selectable -- and so the content has to be escaped,
      -- because a label can carry a frame title straight out of a user's file.
      let labelled =
            diagramWithExtent
              (Box (V2 0 0) (V2 1 1))
              [Label (Colour "#1a1a1a") 14 (V2 0 1) "1 & <2>"]
          out = renderSvg testPage labelled
      out `shouldSatisfy` T.isInfixOf "<text x=\"10\" y=\"10\" font-size=\"14\""
      out `shouldSatisfy` T.isInfixOf ">1 &amp; &lt;2&gt;</text>"

    it "skips a polygon with fewer than three points" $ do
      let sliver =
            diagramWithExtent
              (Box (V2 0 0) (V2 1 1))
              [Polygon (Colour "#abcdef") [V2 0 0, V2 1 1]]
      T.count "<path" (renderSvg testPage sliver) `shouldBe` 0

    it "skips a polyline with fewer than two points" $ do
      let speck =
            diagramWithExtent
              (Box (V2 0 0) (V2 1 1))
              [Polyline (solid (Colour "#000000") 1) [V2 0 0]]
      T.count "<path" (renderSvg testPage speck) `shouldBe` 0

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

    -- Four faces meeting at one vertex, which is what pins the ordering: every
    -- fill comes before every crease, so the creases radiating from the centre
    -- are not painted over by the face next door.
    it "renders quarter-fold.fold, whose four faces meet at a point" $
      renderFixture "test/fixtures/quarter-fold.fold"
        >>= goldenText "test/golden/quarter-fold.svg"

    -- The first step of a folding sequence, with the arrow that makes it an
    -- instruction rather than a picture. Everything in this file is derived:
    -- the arrow comes from subtracting two frames, and neither frame says a
    -- word about arrows because FOLD has no way to.
    it "renders the first step of a sequence, arrow and all" $
      renderStep 0 "test/fixtures/quarter-fold-steps.fold"
        >>= goldenText "test/golden/quarter-fold-step-1.svg"

    -- The whole pipeline: three frames, each drawn, each given the arrow for the
    -- fold it asks for, all laid out at one scale and numbered. What comes out
    -- is a page of instructions, and nothing in the file mentions a step number
    -- or an arrow.
    it "renders a whole folding sequence as one numbered page" $
      renderSteps "test/fixtures/quarter-fold-steps.fold"
        >>= goldenText "test/golden/quarter-fold-steps.svg"

    -- These two are 3D folded forms. Before the camera existed they rendered as
    -- flattened top-down projections; these goldens pin the isometric view that
    -- replaced that. They also pin the folded-form notation: every edge solid,
    -- no dash arrays anywhere, because the dashes mean "a fold still to be made"
    -- and these models are already folded.
    -- Computed geometry rather than geometry read from a file: the quarter fold
    -- collapses to one quadrant with four layers, so the golden is a small
    -- square of coincident edges. If the sign convention ever flips, half the
    -- model lands somewhere else and this file changes.
    it "renders quarter-fold.fold after folding it" $
      renderFolded topDown "test/fixtures/quarter-fold.fold"
        >>= goldenText "test/golden/quarter-fold-folded.svg"

    it "renders simple.fold from the isometric view" $
      renderFixtureFrom FoldedFormNotation isometric "test/fixtures/simple.fold"
        >>= goldenText "test/golden/simple-iso.svg"

    it "renders squaretwist.fold from the isometric view" $
      renderFixtureFrom FoldedFormNotation isometric "test/fixtures/squaretwist.fold"
        >>= goldenText "test/golden/squaretwist-iso.svg"
