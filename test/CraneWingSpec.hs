-- | Check the actual crane independently of its interval certificate. These
-- measurements sample exported poses; they do not replace the whole-path check.
module CraneWingSpec (spec) where

import Control.Monad (forM_)
import CraneGallery (craneSvg)
import CraneWing
import Data.Aeson (eitherDecode, encode)
import Data.IntMap.Strict qualified as IM
import Data.List (nub, sort)
import Data.Set qualified as S
import Data.Text qualified as T
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep
import Senbazuru.Origami.Stacking (solveStacking)
import Senbazuru.Origami.Surface
import Test.Golden (goldenText)
import Test.Hspec

spec :: Spec
spec = describe "checked crane wing" $ do
  source <- runIO (loadFoldFile "examples/crane.fold" >>= right)
  wing <- runIO (right (buildCraneWing (keyFrame source)))
  states <- runIO (right (craneStates wing))
  it "adds only four wing creases and keeps the original folded crane in place" $ do
    reference <- right (foldFrameWith (keyFrame source))
    expected <- right (frameVertices (foldedFrame reference))
    let start = foldedFrame (craneStart wing)
    actual <- right (frameVertices start)
    length actual `shouldBe` 63
    length (facesVertices start) `shouldBe` 76
    length (craneHinge wing) `shouldBe` 4
    length (flapMovingFaces (craneOpening wing)) `shouldBe` 4
    zipWith (\a b -> norm (a ^-^ b)) expected actual `shouldSatisfy` all (< 1e-12)
    forM_ [vertex | (i, (u, v)) <- zip (map EdgeId [0 ..]) (edgesVertices start), i `elem` craneHinge wing, vertex <- [u, v]] $ \vid -> do
      p <- require "crease vertex" (lookup vid (zip (map VertexId [0 ..]) actual))
      abs (v3y p - 0.25) `shouldSatisfy` (< 1e-12)

  it "accepts the entire outward turn and refuses departure through the other wing" $ do
    sweepOutcome (flapCheck (craneOpening wing)) `shouldBe` SweepClear
    sweepIntervals (flapCheck (craneOpening wing)) `shouldSatisfy` (> 0)
    craneRefusal wing `shouldSatisfy` (not . T.null)
    case prepareFlapAlong (craneHinge wing) (craneSide wing) (-90) (craneStart wing) >>= checkFlap defaultSweepSettings of
      Left (FlapEndpointOrder 0 _) -> pure ()
      other -> expectationFailure (show other)

  it "tucks every tail layer between both sides of the body" $ do
    reference <- right (foldFrameWith (keyFrame source))
    let start = foldedFrame (craneStart wing)
        sourceRings = facesVertices (foldedPattern reference)
        rings = zip (map FaceId [0 ..]) (facesVertices start)
        tailFaces = [fid | (fid, ring) <- rings, VertexId 0 `elem` ring]
        -- Two body panels below the tail and their counterparts above it.
        -- The first pair covers the root below folded y=0.5; the second
        -- covers its remaining strip above that line. Resolve their ids
        -- through unchanged material rings after the new wing is cut.
        bodyFace i = do
          ring <- require "original body panel" (lookup i (zip [0 :: Int ..] sourceRings))
          require "re-traced body panel" (lookup (sort ring) [(sort r, fid) | (fid, r) <- rings])
    below <- traverse bodyFace [27, 65]
    above <- traverse bodyFace [29, 66]
    let required = S.fromList ([(b, t) | b <- below, t <- tailFaces] ++ [(t, a) | t <- tailFaces, a <- above])
    length tailFaces `shouldBe` 8
    -- Check the geometric meaning, not the numeric stacking index or an SVG
    -- colour. The previous default is a valid contact arrangement but fails
    -- this conventional-crane requirement.
    firstOrder <- right (solveStacking start)
    firstPairs <- worldOrder start {faceOrders = firstOrder}
    required `S.isSubsetOf` firstPairs `shouldBe` False
    forM_ states $ \(_, sheet) -> do
      actual <- worldOrder (surfaceFrame sheet)
      required `S.isSubsetOf` actual `shouldBe` True

  it "keeps lengths, shared vertices, crease angles, fixed faces and contact valid" $ do
    let material = foldedPattern (craneStart wing)
        topology = facesVertices material
        moving = flapMovingFaces (craneOpening wing)
    materialPoints <- zip (map VertexId [0 ..]) <$> right (frameVertices material)
    initial <- zip (map VertexId [0 ..]) <$> right (frameVertices (foldedFrame (craneStart wing)))
    forM_ [0, 0.17, 0.51, 0.83, 1] $ \t -> do
      sheet <- right (flapAt (craneOpening wing) t)
      let fr = surfaceFrame sheet
      facesVertices fr `shouldBe` topology
      -- The unchanged starting fixture already has relative error 1.4e-11
      -- on its shortest edges; the turn must stay below 1e-10.
      materialError sheet `shouldSatisfy` (< 1e-10)
      placed <- zip (map VertexId [0 ..]) <$> right (frameVertices fr)
      tip <- require "moving wing tip" (lookup (VertexId 2) placed)
      let angle = t * pi / 2
          expectedTip = V3 1 (0.25 - 0.25 * cos angle) (negate (0.25 * sin angle))
      norm (tip ^-^ expectedTip) `shouldSatisfy` (< 1e-12)
      folded <- right (foldFrameWith material {edgesFoldAngle = edgesFoldAngle fr, faceOrders = faceOrders fr})
      forM_ (zip (map FaceId [0 ..]) topology) $ \(fid, ring) -> do
        transform <- require "face transform" (IM.lookup (unFaceId fid) (foldedPlacements folded))
        forM_ ring $ \vid -> do
          p <- require "material vertex" (lookup vid materialPoints)
          q <- require "placed vertex" (lookup vid placed)
          norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-11)
          if fid `elem` moving
            then pure ()
            else do
              was <- require "fixed vertex" (lookup vid initial)
              norm (was ^-^ q) `shouldSatisfy` (< 1e-12)
      faces <- right (frameFaces fr)
      forM_ (zip (edgesVertices fr) (edgesFoldAngle fr)) $ \((a, b), requested) ->
        case [f | f <- faces, a `elem` faceVertexIds f, b `elem` faceVertexIds f] of
          [fixed, flap] -> do
            let (from, to) = if (a, b) `elem` ringEdges (faceVertexIds fixed) then (a, b) else (b, a)
            p <- require "edge start" (lookup from placed)
            q <- require "edge end" (lookup to placed)
            let axis = unit (q ^-^ p)
                n = unit (polygonNormal (faceCorners fixed))
                m = unit (polygonNormal (faceCorners flap))
                difference = negate (180 / pi * atan2 (dot axis (cross n m)) (dot n m)) - requested
            minimum (map abs [difference, difference - 360, difference + 360]) `shouldSatisfy` (< 1e-8)
          _ -> pure ()
      forM_ [(f, g) | f <- faces, g <- faces, faceId f < faceId g] $ \(f, g) -> do
        let orders = [o | o <- faceOrders fr, (orderFace o == faceId f && orderRelativeTo o == faceId g) || (orderFace o == faceId g && orderRelativeTo o == faceId f)]
        (direction, ordered) <- case orders of
          [] -> pure (V3 0 0 1, [])
          o : _ -> do
            relative <- require "order-relative panel" (lookup (orderRelativeTo o) [(faceId h, h) | h <- faces])
            pure (unit (polygonNormal (faceCorners relative)), [if orderStacking o == Above then (name (orderRelativeTo o), name (orderFace o)) else (name (orderFace o), name (orderRelativeTo o))])
        report <- right (checkPanelContact direction ordered [Panel (name (faceId h)) (faceCorners h) | h <- [f, g]])
        contactPassed report `shouldBe` True

  it "round-trips the four illustrations with material coordinates and orders" $ do
    let file = craneFile states
    eitherDecode (encode file) `shouldBe` Right file
    forM_ (zip (otherFrames file) states) $ \(fr, (_, original)) -> do
      reloaded <- right (surfaceFromFrame fr)
      map sampleMaterial (surfaceSamples reloaded) `shouldBe` map (Just . sampleMaterial) (surfaceSamples original)
      faceOrders (surfaceFrame reloaded) `shouldBe` faceOrders (surfaceFrame original)

  it "renders four reviewed illustrations with one camera and scale" $
    right (craneSvg (craneFile states)) >>= goldenText "test/golden/checked-crane.svg"

materialError :: Surface V2 -> Double
materialError sheet = maximum (0 : errors)
  where
    points = zip (map VertexId [0 ..]) (surfaceSamples sheet)
    pairs = nub [(a, b) | ring <- facesVertices (surfaceFrame sheet), a <- ring, b <- ring, a < b]
    errors = [abs (norm (position p ^-^ position q) / norm (sampleMaterial p ^-^ sampleMaterial q) - 1) | (a, b) <- pairs, Just p <- [lookup a points], Just q <- [lookup b points]]

-- FOLD signs refer to the second face's normal. Convert to world -z -> +z
-- pairs before asking whether the fixed tail lies between the fixed body.
worldOrder :: Frame -> IO (S.Set (FaceId, FaceId))
worldOrder fr = do
  faces <- right (frameFaces fr)
  S.fromList <$> traverse (pair faces) (faceOrders fr)
  where
    pair faces o = do
      relative <- require "relative face" (lookup (orderRelativeTo o) [(faceId f, f) | f <- faces])
      let above = (orderStacking o == Above) == (v3z (polygonNormal (faceCorners relative)) > 0)
      pure (if above then (orderRelativeTo o, orderFace o) else (orderFace o, orderRelativeTo o))

unit :: V3 -> V3
unit v = (1 / norm v) *^ v

name :: FaceId -> T.Text
name = T.pack . show . unFaceId

require :: String -> Maybe a -> IO a
require label = maybe (fail ("missing " ++ label)) pure

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
