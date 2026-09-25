module AngleContactSpec (spec) where

import AngleContact
import ContactQuadratic qualified as Q
import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Text qualified as T
import Senbazuru.Fold.Types
import Senbazuru.Geometry.Rigid (identity)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "contact-aware crease angles" $ do
  it "uses original material adjacency despite temporary independent corners" $ do
    input <- stripInput
    m <- right (measureAngles input (stripAngles 170))
    let targets = [t | (_, _, t) <- measuredGaps m]
    targets `shouldSatisfy` elem 0
    targets `shouldSatisfy` elem 1e-6
    provisional <- right (provisionalTriangles input (stripAngles 170))
    length (samples provisional) `shouldBe` 3 * length (triangles (contactMaterial input))
  it "gives every actual loop and contact row a feasible common bound" $ do
    input <- stripInput
    (_, _, common, rows) <- right (angleContactProblem input (stripAngles 170))
    common `shouldSatisfy` (>= 0)
    map constraintOffset rows `shouldSatisfy` all (>= 0)
    let contactRows = filter (T.isPrefixOf "contact " . constraintName) rows
    m <- right (measureAngles input (stripAngles 170))
    length contactRows `shouldBe` length (measuredGaps m)
    contactRows `shouldSatisfy` (not . null)
  it "differentiates moving overlap corners with respect to an angle" $ do
    input <- stripInput
    (_, _, _, rows) <- right (angleContactProblem input (stripAngles 168))
    plus <- right (measureAngles input (stripAngles (168 + 1e-4)))
    minus <- right (measureAngles input (stripAngles (168 - 1e-4)))
    at <- right (measureAngles input (stripAngles 168))
    let contactRows = filter (T.isPrefixOf "contact " . constraintName) rows
        gaps m = [g | (_, g, _) <- measuredGaps m]
        extreme m = minimum (gaps m)
        numerical = (extreme plus - extreme minus) / 2e-4
        selected = [row | (row, (_, g, _)) <- zip contactRows (measuredGaps at), abs (g - extreme at) < 1e-10]
    selected `shouldSatisfy` (not . null)
    abs numerical `shouldSatisfy` (> 1e-4)
    forM_ selected $ \row -> do
      let V3 derivative _ _ = IM.findWithDefault (V3 0 0 0) 1 (constraintGradient row)
      abs (derivative * 0.01 - numerical) `shouldSatisfy` (< 1e-7)
  it "keeps a refused zero-budget contact seed without claiming success" $ do
    input <- stripInput
    -- Both directions cannot hold for overlapping paper, but either one can
    -- be used as a diagnostic requirement. Select the violated direction.
    a <- right (measureAngles input (stripAngles 170))
    let chosen = if measuredWorst a > 1e-5 then input else input {contactOrders = map (\(x, y) -> (y, x)) (contactOrders input)}
    run <- right (contactAngleSearch 0 chosen (stripAngles 170))
    contactAngleStop run `shouldBe` "correction-budget"
    length (contactAngleHistory run) `shouldBe` 1
    contactAngleAttempts run `shouldSatisfy` null
  it "refuses an unverified coupled-vertex direction without storing a trial" $ do
    let r = sqrt 0.5
        source = emptyFrame {verticesCoords = [[0, 0], [1, 0], [r, r], [-1, 0], [r, -r]], edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (0, 2), (0, 3), (0, 4), (1, 2), (2, 3), (3, 4), (4, 1)]], edgesAssignment = [Mountain, Valley, Valley, Valley, Border, Border, Border, Border], facesVertices = map (map VertexId) [[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1]]}
    input <- inputFrom source []
    run <- right (contactAngleSearch 40 input [-175, 175, 175, 175, 0, 0, 0, 0])
    let history = contactAngleHistory run
    map measuredDegrees history `shouldBe` [[-175, 175, 175, 175, 0, 0, 0, 0]]
    contactAngleStop run `shouldBe` "linear-failure"
    case contactAngleAttempts run of
      [attempt] -> do
        attemptTrials attempt `shouldSatisfy` null
        attemptFailure attempt `shouldBe` Just "original-row verification failed"
        case attemptReport attempt of
          Just report -> do
            Q.quadraticConverged report `shouldBe` False
            Q.quadraticViolation report `shouldSatisfy` (> 1e-12)
          Nothing -> expectationFailure "expected an independently refused direction"
      _ -> expectationFailure "expected one bounded direction attempt"
  it "recognizes a joined strip with its actual layer order" $ do
    input <- stripInput
    let ordered = input {contactOrders = map (\(a, b) -> (b, a)) (contactOrders input)}
    run <- right (contactAngleSearch 40 ordered (stripAngles 170))
    contactAngleStop run `shouldBe` "construction-targets"
    contactAngleAttempts run `shouldSatisfy` null
    _ <- right (foldFrameWith (contactPattern ordered) {edgesFoldAngle = stripAngles 170})
    pure ()
  it "refuses changed anchors, signs, flat angles and work budgets" $ do
    input <- stripInput
    contactAngleSearch 41 input (stripAngles 170) `shouldSatisfy` isLeft
    contactAngleSearch (-1) input (stripAngles 170) `shouldSatisfy` isLeft
    contactAngleSearch 0 input (175 : drop 1 (stripAngles 170)) `shouldSatisfy` isLeft
    contactAngleSearch 0 input (-174 : drop 1 (stripAngles 170)) `shouldSatisfy` isLeft
    contactAngleSearch 0 input (take 2 (stripAngles 170) ++ replicate 8 1) `shouldSatisfy` isLeft

stripAngles :: Double -> [Double]
stripAngles x = [-175, x] ++ replicate 8 0

stripInput :: IO AngleContactInput
stripInput = inputFrom source [(FaceId 0, FaceId 1), (FaceId 1, FaceId 2)]
  where
    source = emptyFrame {verticesCoords = [[0, 0], [1, 0], [2, 0], [3, 0], [0, 1], [1, 1], [2, 1], [3, 1]], edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(1, 5), (2, 6), (0, 1), (1, 2), (2, 3), (3, 7), (7, 6), (6, 5), (5, 4), (4, 0)]], edgesAssignment = [Mountain, Valley] ++ replicate 8 Border, facesVertices = map (map VertexId) [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6]]}

inputFrom :: Frame -> [(FaceId, FaceId)] -> IO AngleContactInput
inputFrom source orders = do
  folded <- right (foldFrameWith source {edgesFoldAngle = replicate (length (edgesVertices source)) 0})
  surface <- right (surfaceFromFolded folded)
  refined <- right (refineSurfaceWithEdges 0 surface)
  pure (AngleContactInput source (refinedMesh refined) (refinedPanels refined) orders identity)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
