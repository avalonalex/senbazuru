module FoldBendingSpec (spec) where

import Data.IntMap.Strict qualified as IM
import FoldBending
import FoldContact
import FoldMaterial
import FoldRelaxation
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Test.Hspec

spec :: Spec
spec = describe "crease and panel bending" $ do
  it "measures the single fold's known signed angle and zero panel bending" $ do
    let mesh = sharpMesh 2 Single
    hinges <- right (buildHinges defaultBending defaultPacketRestAngles Single mesh)
    mapM_
      ( \h -> do
          (angle, _) <- right (hingeAngle h (indexed mesh))
          let expected = if hingeRole h == FirstCrease then pi - asin (2 * opening) else 0
          abs (angleError angle expected) `shouldSatisfy` (< 1e-12)
      )
      hinges
  it "differentiates all four corners, including a skew hinge away from flat" $ do
    let points = [V3 0.2 0.1 0.3, V3 1.4 0.2 0.5, V3 0.7 1.2 (-0.1), V3 0.4 (-0.8) 1.1]
        mesh = Mesh (map (materialSample 0 0) points) []
        hinge = Hinge (0, 1, 2, 3) PanelBend 0 1
        epsilon = 1e-6
    (_, gradient) <- right (hingeAngle hinge (indexed mesh))
    mapM_
      ( \(i, g) ->
          mapM_
            ( \axis -> do
                let moved sign = IM.adjust (\s -> s {position = position s ^+^ (sign * epsilon *^ axis)}) i (indexed mesh)
                (plus, _) <- right (hingeAngle hinge (moved 1))
                (minus, _) <- right (hingeAngle hinge (moved (-1)))
                abs (angleError plus minus / (2 * epsilon) - dot g axis) `shouldSatisfy` (< 1e-8)
            )
            [V3 1 0 0, V3 0 1 0, V3 0 0 1]
      )
      gradient
  it "does not mistake valid lengths for an elastic equilibrium" $ do
    let mesh = sharpMesh 2 Single
    result <- right (relaxBending (Settings 0 1e-5) defaultBending defaultPacketRestAngles Single mesh)
    converged result `shouldBe` False
    map checkpointMesh (checkpoints result) `shouldBe` [mesh]
  it "does not certify equilibrium when excessive stiffness overflows the linear solve" $ do
    let settings = defaultBending {creaseStiffness = 1e300, panelStiffness = 1e300}
    result <- right (relaxBending (Settings 1 1e-5) settings defaultPacketRestAngles Single (sharpMesh 1 Single))
    converged result `shouldBe` False
  it "reaches the known single-fold equilibrium without prescribing its positions" $ do
    let mesh = sharpMesh 4 Single
        targets = defaultPacketRestAngles {firstRestAngle = 150 * pi / 180}
    hinges <- right (buildHinges defaultBending targets Single mesh)
    result <- right (relaxBending defaultSettings defaultBending targets Single mesh)
    final <- finalMesh result
    converged result `shouldBe` True
    verifyMaterial Single mesh final
    (crease, panel) <- right (bendingEnergy hinges final)
    crease `shouldSatisfy` (< 1e-12)
    panel `shouldSatisfy` (< 1e-11)
    mapM_
      ( \h -> do
          (angle, _) <- right (hingeAngle h (indexed final))
          abs (angleError angle (hingeRest h)) `shouldSatisfy` (< 1e-6)
      )
      hinges
  it "trades crease accuracy for flatter panels without losing lengths or packet order" $ do
    let mesh = sharpMesh 4 Double
        run stiffness = do
          let settings = defaultBending {panelStiffness = stiffness}
          hinges <- right (buildHinges settings defaultPacketRestAngles Double mesh)
          result <- right (relaxBending defaultSettings settings defaultPacketRestAngles Double mesh)
          converged result `shouldBe` True
          final <- finalMesh result
          verifyMaterial Double mesh final
          (crease, panel) <- right (bendingEnergy hinges final)
          pure (crease, panel / stiffness)
    (softCrease, softBend) <- run 0.2
    (stiffCrease, stiffBend) <- run 5
    stiffCrease `shouldSatisfy` (> softCrease)
    stiffBend `shouldSatisfy` (< softBend / 10)
  it "preserves energy under a rigid rotation and translation of the whole sheet" $ do
    let mesh = sharpMesh 3 Double
        rigid (V3 x y z) = V3 (3 - y) (z - 2) (1 - x)
        moved = mesh {samples = [s {position = rigid (position s)} | s <- samples mesh]}
    hinges <- right (buildHinges defaultBending defaultPacketRestAngles Double mesh)
    (c, p) <- right (bendingEnergy hinges mesh)
    (c', p') <- right (bendingEnergy hinges moved)
    abs (c - c') `shouldSatisfy` (< 1e-12)
    abs (p - p') `shouldSatisfy` (< 1e-12)
  it "keeps crease stiffness constant when the same straight fold is subdivided" $ do
    let energy n = do
          let mesh = sharpMesh n Single
          hinges <- right (buildHinges defaultBending defaultPacketRestAngles Single mesh)
          fst <$> right (bendingEnergy hinges mesh)
    coarse <- energy 1
    fine <- energy 8
    abs (fine - coarse) `shouldSatisfy` (< 1e-12)
  it "gives the second fold opposite signs through the two material halves" $ do
    hinges <- right (buildHinges defaultBending defaultPacketRestAngles Double (sharpMesh 2 Double))
    let second = [hingeRest h | h <- hinges, hingeRole h == SecondCrease]
    length (filter (> 0) second) `shouldBe` 2
    length (filter (< 0) second) `shouldBe` 2
    sum second `shouldSatisfy` ((< 1e-12) . abs)
  it "keeps the intended signed branch near a fully closed crease" $ do
    abs (angleError (pi - 1e-6) (-pi) + 1e-6) `shouldSatisfy` (< 1e-12)
    abs (angleError (-pi + 1e-6) pi - 1e-6) `shouldSatisfy` (< 1e-12)
  it "does not weld disconnected material edges at coincident spatial positions" $ do
    let a = materialSample 0 0 (V3 0 0 0)
        b = materialSample 1 0 (V3 1 0 0)
        c = materialSample 0 1 (V3 0 1 0)
        mesh = Mesh [a, b, c, a, b, c] [(0, 1, 2), (3, 4, 5)]
    buildHinges defaultBending defaultPacketRestAngles Single mesh `shouldBe` Right []
  it "rejects invalid stiffness, winding, adjacency and collapsed angular geometry" $ do
    let mesh = sharpMesh 1 Single
    buildHinges (defaultBending {panelStiffness = 0}) defaultPacketRestAngles Single mesh `shouldBe` Left InvalidBending
    buildHinges defaultBending (defaultPacketRestAngles {firstRestAngle = 0 / 0}) Single mesh `shouldBe` Left InvalidBending
    buildHinges defaultBending defaultPacketRestAngles Single (mesh {triangles = [(0, 1, 1000)]}) `shouldBe` Left (MissingHingeVertex 1000)
    buildHinges defaultBending defaultPacketRestAngles Single (mesh {triangles = [(0, 3, 1)]}) `shouldBe` Left (InvalidMaterialTriangle 0)
    buildHinges defaultBending defaultPacketRestAngles Single (mesh {triangles = [(0, 1, 3), (0, 1, 3)]}) `shouldBe` Left (InvalidHingeEdge 0 1)
    hinges <- right (buildHinges defaultBending defaultPacketRestAngles Single mesh)
    case hinges of
      h : _ -> do
        let (a, b, _, _) = hingeVertices h
        hingeAngle h (IM.map (\s -> s {position = V3 0 0 0}) (indexed mesh)) `shouldBe` Left (CollapsedHinge a b)
      [] -> expectationFailure "fixture should have interior hinges"

verifyMaterial :: FoldCase -> MaterialMesh -> MaterialMesh -> Expectation
verifyMaterial which original final = do
  maxLengthError final `shouldSatisfy` (<= lengthTolerance defaultSettings)
  triangles final `shouldBe` triangles original
  map sampleMaterial (samples final) `shouldBe` map sampleMaterial (samples original)
  componentCount final `shouldBe` 1
  abs (areaRatio final - 1) `shouldSatisfy` (< 1e-5)
  let contact = packetCheck which final
  uncheckedTriangles contact `shouldBe` 0
  violatingPairs contact `shouldBe` 0
  maxOrderViolation contact `shouldSatisfy` (<= contactTolerance)

finalMesh :: Relaxation -> IO MaterialMesh
finalMesh result = case reverse (checkpoints result) of
  point : _ -> pure (checkpointMesh point)
  [] -> expectationFailure "missing final checkpoint" >> fail "empty relaxation"

indexed :: MaterialMesh -> IM.IntMap MaterialSample
indexed = IM.fromList . zip [0 ..] . samples

right :: (Show e) => Either e a -> IO a
right (Right value) = pure value
right (Left err) = expectationFailure (show err) >> fail "unexpected Left"
