-- | Releasing a root hold must not release an unrelated layer or silently
-- drop its contacts. Soft root preferences and preserved original folds have
-- different acceptance rules, exercised with a solved control and a bad grip.
module CraneRootSpec (spec) where

import Control.Monad (forM_)
import CraneRoot
import CraneSpread
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (minimumBy)
import Data.Ord (comparing)
import Data.Set qualified as S
import FoldBending
import FoldMaterial (componentCount)
import FoldRelaxation
import RigidBase (goldenSection, sidesPass)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec
import WingBending (finalMesh)

spec :: Spec
-- Each example owns its solver state; any shared fixture is immutable.
spec = parallel $ beforeAll load $ describe "the crane wing-to-body transition" $ do
  it "changes holds and root preferences without changing the sheet or tip grip" $ \source -> do
    held <- right (craneRoot source 3 HeldRoot)
    let baseline = rootSpread held
    forM_ [ReleasedRoot, WeakerRoot, FlatRoot, FreeBody] $ \control -> do
      study <- right (craneRoot source 3 control)
      let fixture = rootSpread study
      refinedMesh (spreadRefined fixture) `shouldBe` refinedMesh (spreadRefined baseline)
      spreadMesh fixture `shouldBe` spreadMesh baseline
      spreadOrders fixture `shouldBe` spreadOrders baseline
      spreadGrip fixture `shouldBe` spreadGrip baseline
      rootNeighbours study `shouldBe` S.fromList (map FaceId [7, 8, 27, 43])
      forM_ (S.toList (spreadGrip fixture)) $ \i -> IM.lookup i (spreadPins fixture) `shouldBe` IM.lookup i (spreadPins baseline)
      IM.size (spreadPins fixture) `shouldSatisfy` (< IM.size (spreadPins baseline))
      let original hinges = [h | h <- hinges, SurfaceCrease eid <- [hingeRole h], S.notMember eid (rootEdges study)]
      original (spreadHinges fixture) `shouldBe` original (spreadHinges baseline)
    componentCount (spreadMesh baseline) `shouldBe` 1
    length (spreadOrders baseline) `shouldBe` 902

  -- A base is the paper between the wing's widest point and a hinge above it.
  -- A hinge below the widest point has none, and the control is unchanged.
  it "turns a released control's base about the hinge only above the widest point" $ \source -> do
    low <- right (craneRoot source 3 FlatRoot)
    let kept = rootSpread (rigidBase 28 low (spreadMesh (rootSpread low)))
    spreadPins kept `shouldBe` spreadPins (rootSpread low)
    spreadMesh kept `shouldBe` spreadMesh (rootSpread low)
    high <- right (craneRootAt 0.376 source 3 FlatRoot)
    S.size (rootEdges high) `shouldBe` 8
    S.size (rootNeighbours high) `shouldBe` 8
    let fixture = rootSpread high
        theta = 28
        turn = theta * pi / 180
        hingeY = rootHingeY high
        widest = rootWidest high
        turned = rootSpread (rigidBase theta high (spreadMesh fixture))
        added = IM.difference (spreadPins turned) (spreadPins fixture)
        flat = IM.fromList (zip [0 ..] (map position (samples (refinedMesh (spreadRefined fixture)))))
        start = IM.fromList (zip [0 ..] (map position (samples (spreadMesh turned))))
    IM.size added `shouldSatisfy` (> 8)
    IM.isSubmapOf (spreadPins fixture) (spreadPins turned) `shouldBe` True
    forM_ (IM.toList added) $ \(i, q@(V3 _ qy qz)) -> do
      V3 _ y _ <- maybe (fail "missing vertex") pure (IM.lookup i flat)
      y `shouldSatisfy` (>= widest - 1e-9)
      abs (qz * cos turn - (qy - hingeY) * sin turn) `shouldSatisfy` (< 1e-12)
      IM.lookup i start `shouldBe` Just q
    -- The base's far edge, along the widest point, drops by (h - w) sin theta.
    abs (minimum [z | V3 _ _ z <- IM.elems added] + (hingeY - widest) * sin turn) `shouldSatisfy` (< 1e-12)
    -- A held control already holds its base at 30 degrees and keeps it there.
    held <- right (craneRootAt 0.376 source 3 HeldRoot)
    spreadPins (rootSpread (rigidBase theta held (spreadMesh (rootSpread held)))) `shouldBe` spreadPins (rootSpread held)

  -- The base search narrows 15 to 45 degrees by the golden ratio until the
  -- bracket is under 0.05 degree: two evaluations, then one per narrowing,
  -- fourteen of them. Each solve after the first two starts from the mesh of
  -- the bracket point beside it, which is always the nearest point already
  -- evaluated: the new point lies 0.236 of the bracket from it and 0.382 from
  -- the nearer end.
  it "finds a minimum by golden section, handing each evaluation a neighbour's start" $ \_ -> do
    let phi = (sqrt 5 - 1) / 2
        f :: [Double] -> Double -> Either () (Double, [Double])
        f seen x = Right ((x - 28.4) ^ (2 :: Int), x : seen)
    ((x, fx, chain), evaluations) <- either (const (fail "the search failed")) pure (goldenSection 0.05 15 45 [] f)
    let tried = [(t, ft) | (t, ft, _) <- evaluations]
    abs (x - 28.4) `shouldSatisfy` (< 0.05)
    fx `shouldBe` (x - 28.4) ^ (2 :: Int)
    length tried `shouldBe` 16
    take 2 (map fst tried) `shouldBe` [45 - phi * 30, 15 + phi * 30]
    map fst tried `shouldSatisfy` all (\t -> t > 15 && t < 45)
    -- Each evaluation is reported with the payload its own call made, and the
    -- winner with its own. Handing an evaluation the first start, or the far
    -- bracket point's, breaks the last line.
    take 1 chain `shouldBe` [x]
    evaluations `shouldSatisfy` all (\(t, _, made) -> take 1 made == [t])
    let nearest t = minimumBy (comparing (\u -> abs (u - t)))
    [take 1 (drop 1 made) | (_, _, made) <- drop 2 evaluations]
      `shouldBe` [[nearest t [u | (u, _, _) <- take k evaluations]] | (k, (t, _, _)) <- drop 2 (zip [0 ..] evaluations)]

  it "activates body contacts when body vertices become free and keeps the distant boundary held" $ \source -> do
    fixed <- rootSpread <$> right (craneRoot source 3 FlatRoot)
    study <- right (craneRoot source 3 FreeBody)
    let fixture = rootSpread study
        allowed = S.union (spreadMoving fixture) (rootNeighbours study)
        vertices (a, b, c) = [a, b, c]
        tagged = zip (triangles (spreadMesh fixture)) (refinedPanels (spreadRefined fixture))
        freePanels = S.fromList [owner | (tri, owner) <- tagged, any (`IM.notMember` spreadPins fixture) (vertices tri)]
    freePanels `shouldBe` allowed
    forM_ [(i, owner) | (tri, owner) <- tagged, S.notMember owner allowed, i <- vertices tri] $ \(i, _) ->
      IM.lookup i (spreadPins fixture) `shouldBe` IM.lookup i (spreadPins fixed)
    let extra = S.fromList (spreadContactOrders fixture) S.\\ S.fromList (spreadContactOrders fixed)
    extra `shouldSatisfy` (not . S.null)
    extra `shouldSatisfy` all (\(a, b) -> S.notMember a (spreadMoving fixture) && S.notMember b (spreadMoving fixture))
    -- Original source pairs are retained; additional transitive requirements
    -- may be necessary through held material between two declared relations.
    S.fromList [(a, b) | (a, b) <- spreadOrders fixture, S.member a freePanels || S.member b freePanels] `shouldSatisfy` (`S.isSubsetOf` S.fromList (spreadContactOrders fixture))
    let inherited = fixed {spreadOrders = [(FaceId 5, FaceId 7), (FaceId 7, FaceId 0)]}
    spreadContactOrders inherited `shouldContain` [(FaceId 5, FaceId 0)]
    spreadContactOrders inherited `shouldNotContain` [(FaceId 7, FaceId 0)]

  it "accepts a soft flat preference without pretending that the root became flat" $ \source -> do
    study <- right (craneRoot source 3 FlatRoot)
    let fixture = rootSpread study
    result <- right (solveSpread (Settings 40 1e-5) fixture)
    mesh <- right (finalMesh result)
    right (rootAccepted study result mesh) `shouldReturn` True
    spreadHeldError fixture mesh `shouldBe` 0
    rootBodyMovement study mesh `shouldBe` 0
    maxLengthError mesh `shouldSatisfy` (< 1e-6)
    angles <- map (abs . snd) <$> right (rootAngles study mesh)
    minimum angles `shouldSatisfy` (> 25 * pi / 180)
    maximum angles `shouldSatisfy` (< 30 * pi / 180)
    right (originalCreaseError study mesh) >>= (`shouldSatisfy` (< 1e-5))
    -- A small root residual is NOT the success gate: the original held-root
    -- acceptance would reject this deliberately different material preference.
    right (spreadAccepted fixture result mesh) `shouldReturn` False
    right (rootAccepted study result {converged = False} mesh) `shouldReturn` False
    profile <- right (rootProfile study mesh)
    length profile `shouldSatisfy` (> 8)
    exported <- right (spreadSurface fixture mesh)
    surfaceSamples exported `shouldBe` samples mesh
    rootProfile study mesh {triangles = []} `shouldSatisfy` isLeft

  it "still rejects an upper grip forced through its partner after releasing the root" $ \source -> do
    original <- right (craneRoot source 3 FlatRoot)
    let study = original {rootSpread = crossedGrip (rootSpread original)}
        fixture = rootSpread study
    contact <- right (spreadCheck fixture (spreadMesh fixture))
    reversedOrders contact `shouldSatisfy` (not . null)
    result <- right (solveSpread (Settings 2 1e-5) fixture)
    mesh <- right (finalMesh result)
    right (rootAccepted study result mesh) `shouldReturn` False
    spreadHeldError fixture mesh `shouldBe` 0

  -- Owner decision 36: a side refuses the reused angle only by ending with
  -- strictly less bending energy, and an unconverged side counts all the same.
  it "refuses a reused base angle only when a side ends with less bending energy" $ \_ -> do
    sidesPass 0.1 [(27, 0.102, True), (29, 0.101, True)] `shouldBe` True
    sidesPass 0.1 [(27, 0.1, True), (29, 0.1, True)] `shouldBe` True
    sidesPass 0.1 [(27, 0.102, True), (29, 0.099, True)] `shouldBe` False
    sidesPass 0.1 [(27, 0.099, False), (29, 0.102, True)] `shouldBe` False

load :: IO Frame
load = keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
