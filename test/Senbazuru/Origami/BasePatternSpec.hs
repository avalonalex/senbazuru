-- | Traditional bases whose creases meet at the sheet's centre.
--
-- The source files are examples, not copies kept only for testing. Checking
-- their final coordinates independently of the drawing catches a plausible
-- picture of the wrong base. Shared-corner and length checks then distinguish
-- a folded sheet from disconnected faces placed at those same coordinates.
module Senbazuru.Origami.BasePatternSpec (spec) where

import Control.Monad (forM_)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types (Frame (..), VertexId (..), keyFrame)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.FlatFold
import Senbazuru.Origami.Folding
import Senbazuru.Origami.Stacking (defaultBudget, stackingSpace, stateCount)
import Test.Hspec

spec :: Spec
spec = describe "meeting-crease base patterns" $
  forM_ bases $ \(name, expected) -> describe name $ do
    source <- runIO $ keyFrame <$> (loadFoldFile ("examples/" ++ name ++ ".fold") >>= requireRight)
    it "checks one centre with six active creases, leaving two guides flat" $ do
      report <- requireRight (checkFrame defaultTolerance source)
      reportChecked report `shouldBe` [VertexCheck (VertexId 8) 6 0 []]
      length (reportSkipped report) `shouldBe` 8
    it "closes every face around one shared centre without changing edge lengths" $ do
      result <- requireRight (foldFrameWith source)
      let sheet = foldedPattern result
          faces = facesVertices sheet
      original <- vertexMap sheet
      folded <- vertexMap (foldedFrame result)
      -- Eight triangles cover the square using nine shared vertices and
      -- sixteen edges. Every triangle uses the same centre vertex id.
      IM.size original `shouldBe` 9
      IM.size folded `shouldBe` 9
      length (edgesVertices sheet) `shouldBe` 16
      length faces `shouldBe` 8
      faces `shouldSatisfy` all (\ring -> length ring == 3 && VertexId 8 `elem` ring)
      forM_ (zip [0 ..] faces) $ \(faceId, ring) -> do
        placement <- requireJust (IM.lookup faceId (foldedPlacements result))
        forM_ ring $ \(VertexId vertexId) -> do
          sourcePoint <- requireJust (IM.lookup vertexId original)
          foldedPoint <- requireJust (IM.lookup vertexId folded)
          norm (applyRigid placement sourcePoint ^-^ foldedPoint) `shouldSatisfy` (< 1e-12)
      forM_ (edgesVertices sheet) $ \edge -> do
        sourceLength <- edgeLength original edge
        foldedLength <- edgeLength folded edge
        abs (foldedLength - sourceLength) `shouldSatisfy` (< 1e-12)
    it "places the original corners and midpoints in the expected footprint" $ do
      result <- requireRight (foldFrame source)
      actual <- requireRight (frameVertices result)
      length actual `shouldBe` length expected
      forM_ (zip actual expected) $ \(point, target) ->
        norm (point ^-^ target) `shouldSatisfy` (< 1e-12)
    it "has exactly one valid flat stacking without exhausting the search budget" $ do
      result <- requireRight (foldFrame source)
      space <- requireRight (stackingSpace defaultBudget result)
      stateCount space `shouldBe` (1, False)

-- | Corners SW, SE, NE, NW; midpoints S, E, N, W; centre. Coordinates
-- describe the fully collapsed shape with the lower-left triangle held
-- still by the folding routine. The square has side 1/2; the triangle has
-- base 1 and height 1/2. These are geometric expectations, not SVG snapshots.
bases :: [(String, [V3])]
bases =
  [ ( "square-base",
      replicate 4 (V3 0 0 0)
        ++ [V3 0.5 0 0, V3 0 0.5 0, V3 0 0.5 0, V3 0.5 0 0, V3 0.5 0.5 0]
    ),
    ( "waterbomb-base",
      [V3 0 0 0, V3 1 0 0, V3 1 0 0, V3 0 0 0]
        ++ replicate 4 (V3 0.5 0 0)
        ++ [V3 0.5 0.5 0]
    )
  ]

vertexMap :: Frame -> IO (IM.IntMap V3)
vertexMap frame = IM.fromList . zip [0 ..] <$> requireRight (frameVertices frame)

edgeLength :: IM.IntMap V3 -> (VertexId, VertexId) -> IO Double
edgeLength points (VertexId a, VertexId b) = do
  p <- requireJust (IM.lookup a points)
  q <- requireJust (IM.lookup b points)
  pure (norm (p ^-^ q))

requireRight :: (Show e) => Either e a -> IO a
requireRight (Left err) = expectationFailure (show err) >> fail "base fixture failed"
requireRight (Right value) = pure value

requireJust :: Maybe a -> IO a
requireJust Nothing = expectationFailure "missing vertex or face placement" >> fail "base fixture failed"
requireJust (Just value) = pure value
