-- | An entire authored route, independently measured at and between joins.
-- The sweep checks whole turns; these sampled checks additionally verify
-- exported material geometry, achieved angles and the carried layer orders.
module BlintzSequenceSpec (spec) where

import BlintzGallery (blintzSvg)
import BlintzSequence
import Control.Monad (forM_)
import Data.Aeson (eitherDecode, encode)
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Text qualified as T
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep
import Senbazuru.Origami.Surface
import Test.Golden (goldenText)
import Test.Hspec

spec :: Spec
spec = describe "checked blintz sequence" $ do
  source <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  moves <- runIO (right (buildBlintzSequence (keyFrame source)))
  states <- runIO (right (blintzStates moves))
  it "completes four half-turns before reopening the first corner" $ do
    length moves `shouldBe` 5
    length states `shouldBe` 11
    map (sweepOutcome . flapCheck . blintzMotion) moves `shouldBe` replicate 5 SweepClear
    map (flapStationaryFace . blintzMotion) moves `shouldBe` replicate 5 (FaceId 0)
    map (edgesFoldAngle . surfaceFrame . blintzEnd) moves
      `shouldBe` map (replicate 8 0 ++) [[-180, 0, 0, 0], [-180, -180, 0, 0], [-180, -180, -180, 0], replicate 4 (-180), [0, -180, -180, -180]]
    map (length . faceOrders . surfaceFrame . blintzEnd) moves `shouldBe` [1, 2, 3, 4, 3]

  forM_ (zip [1 :: Int ..] moves) $ \(i, move) ->
    it ("preserves lengths, shared corners, signed crease angles and contact throughout move " ++ show i) $ do
      material <- right (frameVertices (foldedPattern (blintzStart move)))
      let materialPoints = zip (map VertexId [0 ..]) material
          originalTopology = facesVertices (foldedPattern (blintzStart move))
      forM_ [0, 0.1 .. 1] $ \t -> do
        sheet <- right (flapAt (blintzMotion move) t)
        let fr = surfaceFrame sheet
        facesVertices fr `shouldBe` originalTopology
        length (surfaceSamples sheet) `shouldBe` 8
        materialError sheet `shouldSatisfy` (< 1e-12)
        points <- right (frameVertices fr)
        let placed = zip (map VertexId [0 ..]) points
        -- Independently place each face's copy of each vertex. All copies
        -- must meet at the one position exported for that material id.
        folded <- right (foldFrameWith (foldedPattern (blintzStart move)) {edgesFoldAngle = edgesFoldAngle fr, faceOrders = faceOrders fr})
        forM_ (zip (map FaceId [0 ..]) originalTopology) $ \(fid, ring) -> do
          transform <- require "face transform" (IM.lookup (unFaceId fid) (foldedPlacements folded))
          forM_ ring $ \vid -> do
            p <- require "material vertex" (lookup vid materialPoints)
            q <- require "placed vertex" (lookup vid placed)
            norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-12)
        faces <- right (frameFaces fr)
        centre <- require "central face" (lookup (FaceId 0) [(faceId f, f) | f <- faces])
        forM_ (faceVertexIds centre) $ \vid -> do
          p <- require "central material vertex" (lookup vid materialPoints)
          q <- require "central placed vertex" (lookup vid placed)
          norm (p ^-^ q) `shouldSatisfy` (< 1e-12)
        forM_ (zip (map EdgeId [0 ..]) (zip (edgesVertices fr) (edgesFoldAngle fr))) $ \(eid, ((a, b), requested)) ->
          if unEdgeId eid < 8
            then pure ()
            else do
              corner <- require "corner face" (lookup eid (zip (map EdgeId [8 ..]) [FaceId 2, FaceId 3, FaceId 4, FaceId 1]) >>= (\fid -> lookup fid [(faceId f, f) | f <- faces]))
              let oriented = if (a, b) `elem` ringEdges (faceVertexIds centre) then (a, b) else (b, a)
              from <- require "hinge start" (lookup (fst oriented) placed)
              to <- require "hinge end" (lookup (snd oriented) placed)
              let axis = unit (to ^-^ from)
                  fixedNormal = unit (polygonNormal (faceCorners centre))
                  movingNormal = unit (polygonNormal (faceCorners corner))
                  measured = negate (180 / pi * atan2 (dot axis (cross fixedNormal movingNormal)) (dot fixedNormal movingNormal))
                  difference = measured - requested
              minimum (map abs [difference, difference - 360, difference + 360]) `shouldSatisfy` (< 1e-9)
        -- All established contacts are corners below the fixed central
        -- diamond. This direction is independent of the FOLD order encoding.
        let ordered = [(name (orderFace o), "0") | o <- faceOrders fr]
        report <- right (checkPanelContact (V3 0 0 1) ordered [Panel (name (faceId f)) (faceCorners f) | f <- faces])
        contactPassed report `shouldBe` True

  it "carries exactly the accepted positions, material ids, angles and orders across each join" $
    forM_ (zip moves (drop 1 moves)) $ \(previous, following) -> do
      start <- right (flapAt (blintzMotion following) 0)
      let end = blintzEnd previous
      faceOrders (surfaceFrame start) `shouldMatchList` faceOrders (surfaceFrame end)
      edgesFoldAngle (surfaceFrame start) `shouldBe` edgesFoldAngle (surfaceFrame end)
      map sampleMaterial (surfaceSamples start) `shouldBe` map sampleMaterial (surfaceSamples end)
      zipWith (\a b -> norm (position a ^-^ position b)) (surfaceSamples start) (surfaceSamples end) `shouldSatisfy` all (< 1e-12)

  it "matches the existing base, with four distinct material corners meeting at its centre" $ do
    completed <- require "completed base" (case drop 3 moves of m : _ -> Just (blintzEnd m); [] -> Nothing)
    reference <- right (foldFrameWith (keyFrame source))
    centreTransform <- require "reference central transform" (IM.lookup 4 (foldedPlacements reference))
    expected <- map (applyRigid (inverse centreTransform)) <$> right (frameVertices (foldedFrame reference))
    actual <- right (frameVertices (surfaceFrame completed))
    length actual `shouldBe` length expected
    zipWith (\a b -> norm (a ^-^ b)) actual expected `shouldSatisfy` all (< 1e-12)
    forM_ (take 4 actual) $ \p -> norm (p ^-^ V3 0.5 0.5 0) `shouldSatisfy` (< 1e-12)
    length (nub (map sampleMaterial (take 4 (surfaceSamples completed)))) `shouldBe` 4
    faceOrders (surfaceFrame completed) `shouldMatchList` [FaceOrder (FaceId i) (FaceId 0) Below | i <- [1 .. 4]]

  it "refuses reopening through the central sheet despite an identical flat endpoint" $ do
    opening <- require "reopening" (case drop 4 moves of m : _ -> Just m; [] -> Nothing)
    wrong <- right (prepareFlap (EdgeId 8) (FaceId 2) (-180) (blintzStart opening))
    case checkFlap defaultSweepSettings wrong of
      Left FlapEndpointOrder {} -> pure ()
      other -> expectationFailure (show other)

  -- The corner lies folded under the centre, upside down. Turned towards -z,
  -- away from the reader, it comes back out; towards +z it would swing up
  -- through the centre, the turn refused above.
  it "turns the folded corner by where it goes, so behind reopens it" $ do
    opening <- require "reopening" (case drop 4 moves of m : _ -> Just m; [] -> Nothing)
    let start = blintzStart opening
    reopen <- right (prepareFlap (EdgeId 8) (FaceId 2) 180 start)
    wrong <- right (prepareFlap (EdgeId 8) (FaceId 2) (-180) start)
    prepareFlapToward [EdgeId 8] (FaceId 2) 180 TowardMinusZ start `shouldBe` Right reopen
    prepareFlapToward [EdgeId 8] (FaceId 2) 180 TowardPlusZ start `shouldBe` Right wrong

  it "round-trips the illustrated states with their material coordinates and orders" $ do
    let file = blintzFile states
    eitherDecode (encode file) `shouldBe` Right file
    forM_ (zip (otherFrames file) states) $ \(fr, (_, original)) -> do
      reloaded <- right (surfaceFromFrame fr)
      map sampleMaterial (surfaceSamples reloaded) `shouldBe` map (Just . sampleMaterial) (surfaceSamples original)
      faceOrders (surfaceFrame reloaded) `shouldBe` faceOrders (surfaceFrame original)

  it "renders a reviewed eleven-figure page with one camera and scale" $ do
    svg <- right (blintzSvg (blintzFile states))
    goldenText "test/golden/checked-blintz.svg" svg

materialError :: Surface V2 -> Double
materialError sheet = maximum (0 : errors)
  where
    points = zip (map VertexId [0 ..]) (surfaceSamples sheet)
    pairs = nub [(a, b) | ring <- facesVertices (surfaceFrame sheet), a <- ring, b <- ring, a < b]
    errors = [abs (norm (position p ^-^ position q) / norm (sampleMaterial p ^-^ sampleMaterial q) - 1) | (a, b) <- pairs, Just p <- [lookup a points], Just q <- [lookup b points]]

unit :: V3 -> V3
unit v = (1 / norm v) *^ v

name :: FaceId -> T.Text
name = T.pack . show . unFaceId

require :: String -> Maybe a -> IO a
require label = maybe (fail ("missing " ++ label)) pure

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
