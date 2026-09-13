module SelfContactSpec (spec) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (sort)
import FoldBending
import FoldContact (ContactRow (..), contactTolerance)
import FoldMaterial (componentCount)
import FoldRelaxation
import PanelContact
import SelfContactExample
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import Test.Hspec

spec :: Spec
spec = describe "self-contact inside a bending panel" $ do
  forM_ [8, 16] $ \count ->
    it ("corrects the contacting curl with " ++ show count ++ " spans") $ do
      fixture <- right (curledPanel count)
      let mesh = curlMesh fixture
          hinges = curlHinges fixture
          model = curlContact fixture
          report current = right (checkLocalTriangleContact axis (curlPairs fixture) current)
      contactPassed <$> report mesh `shouldReturn` True
      free <- right (relaxHinges defaultSettings hinges mesh)
      freeMesh <- finalMesh free
      freeReport <- report freeMesh
      freeGeometry <- right (checkLocalTriangleContact axis [] freeMesh)
      converged free `shouldBe` True
      if count == 8
        then do
          crossingPanels freeReport `shouldSatisfy` (not . null)
          reversedOrders freeReport `shouldSatisfy` (not . null)
        else -- At 24 degrees the sixteen-span strip wraps a fifteen-sided loop,
        -- then overlays its first span. This is positive-area coplanar contact.
          unorderedContacts freeGeometry `shouldSatisfy` (not . null)
      freeRows <- right (Contact.orderedContacts model freeMesh)
      minimum (map contactGap freeRows) `shouldSatisfy` (< negate (curlClearance fixture / 2))
      corrected <- right (relaxSurfaceContact defaultSettings hinges model mesh)
      final <- finalMesh corrected
      finalReport <- report final
      converged corrected `shouldBe` True
      contactPassed finalReport `shouldBe` True
      checkedPanelPairs finalReport `shouldBe` (2 * count * (2 * count - 1) `div` 2)
      rows <- right (Contact.orderedContacts model final)
      rows `shouldSatisfy` (not . null)
      let gap = minimum (map contactGap rows)
      gap `shouldSatisfy` (>= negate contactTolerance)
      gap `shouldSatisfy` (< 1e-5) -- The local contact is active, not avoided by separating everything.
      forM_ (checkpoints corrected) $ \point -> do
        let current = checkpointMesh point
        triangles current `shouldBe` triangles mesh
        map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples mesh)
        componentCount current `shouldBe` 1
      maxLengthError final `shouldSatisfy` (< 1e-5)
      curlOwners fixture `shouldBe` replicate (length (triangles final)) (FaceId 0)
      Contact.prepareContact 0 axis [(FaceId 0, FaceId 0)] (curlOwners fixture) mesh `shouldBe` Left Contact.CyclicContactOrder
      let vertices = IM.fromList (zip [0 ..] (samples freeMesh))
      forM_ [h | h <- hinges, hingeRole h == BendControl] $ \hinge -> do
        (angle, _) <- right (hingeAngle hinge vertices)
        abs (angle - 0.8 * hingeRest hinge) `shouldSatisfy` (< 1e-5)

  it "keeps passive flatness, applied curl and material creases distinct" $ do
    fixture <- right (curledPanel 8)
    let hinges = curlHinges fixture
        passive = filter ((== PanelBend) . hingeRole) hinges
        controls = filter ((== BendControl) . hingeRole) hinges
    length controls `shouldBe` 7
    length passive `shouldBe` 15
    all ((== 0) . hingeRest) passive `shouldBe` True
    all ((`elem` [PanelBend, BendControl]) . hingeRole) hinges `shouldBe` True
    length (curlBoundary fixture) `shouldBe` 18
    maxLengthError (curlMesh fixture) `shouldSatisfy` (< 1e-12)
    (crease, panel) <- right (bendingEnergy hinges (curlMesh fixture))
    crease `shouldBe` 0
    panel `shouldSatisfy` (> 0)

  it "refuses neighboring triangles, including adjacency implied through another pair" $ do
    fixture <- right (curledPanel 8)
    let prepare pairs = Contact.prepareTriangleContact 1e-6 axis pairs (curlMesh fixture)
    prepare [(0, 1)] `shouldBe` Left (Contact.AdjacentContactTriangles 0 1)
    prepare [(0, 8), (8, 1)] `shouldBe` Left (Contact.AdjacentContactTriangles 0 1)
    prepare [(0, 14), (14, 0)] `shouldBe` Left Contact.CyclicContactOrder
    prepare [(0, 0)] `shouldBe` Left Contact.CyclicContactOrder
    prepare [(0, 999)] `shouldBe` Left (Contact.UnknownContactTriangle 999)
    prepare [(-1, 14)] `shouldBe` Left (Contact.UnknownContactTriangle (-1))

  it "does not duplicate forces when the same local requirement is repeated" $ do
    one <- right (Contact.prepareTriangleContact 1e-6 axis [(0, 1)] crossing)
    two <- right (Contact.prepareTriangleContact 1e-6 axis [(0, 1), (0, 1)] crossing)
    one `shouldBe` two

  it "differentiates local contact, including the moving overlap corners" $ do
    model <- right (Contact.prepareTriangleContact 0 axis [(0, 1)] crossing)
    rows <- right (Contact.orderedContacts model crossing)
    let energy mesh = sum . map (\r -> min 0 (contactGap r) ** 2 / 2) <$> right (Contact.orderedContacts model mesh)
        analytic = IM.fromListWith (^+^) [(i, contactGap row *^ gradient) | row <- rows, contactGap row < 0, (i, gradient) <- contactGradient row]
    length rows `shouldSatisfy` (>= 3)
    forM_ [0 .. length (samples crossing) - 1] $ \i ->
      forM_ [V3 1 0 0, V3 0 1 0, V3 0 0 1] $ \direction -> do
        plus <- energy (shiftVertex i (1e-6 *^ direction) crossing)
        minus <- energy (shiftVertex i ((-1e-6) *^ direction) crossing)
        abs ((plus - minus) / 2e-6 - dot direction (IM.findWithDefault (V3 0 0 0) i analytic)) `shouldSatisfy` (< 1e-7)
    report <- right (checkLocalTriangleContact axis [(0, 1)] crossing)
    let independent = maximum (0 : [gap | (_, _, gap) <- reversedOrders report])
    abs (independent + minimum (0 : map contactGap rows)) `shouldSatisfy` (< 1e-12)

  it "keeps local gaps unchanged when the sheet and contact direction move together" $ do
    let rotate (V3 x y z) = V3 z x y
        moved = crossing {samples = [sample {position = rotate (position sample) ^+^ V3 3 (-2) 5} | sample <- samples crossing]}
    original <- right (Contact.prepareTriangleContact 0 axis [(0, 1)] crossing) >>= \model -> right (Contact.orderedContacts model crossing)
    rotated <- right (Contact.prepareTriangleContact 0 (rotate axis) [(0, 1)] moved) >>= \model -> right (Contact.orderedContacts model moved)
    length original `shouldBe` length rotated
    maximum (0 : zipWith (\a b -> abs (a - b)) (sort (map contactGap original)) (sort (map contactGap rotated))) `shouldSatisfy` (< 1e-12)

  it "refuses changes to triangle identities and original material coordinates" $ do
    fixture <- right (curledPanel 8)
    let mesh = curlMesh fixture
        contact = curlContact fixture
    Contact.orderedContacts contact mesh {triangles = reverse (triangles mesh)} `shouldBe` Left Contact.ChangedContactMaterial
    Contact.orderedContacts contact mesh {samples = [s {sampleMaterial = V2 9 9} | s <- samples mesh]} `shouldBe` Left Contact.ChangedContactMaterial

  it "does not attract separated regions or call exhausted corrections settled" $ do
    fixture <- right (curledPanel 8)
    let mesh = curlMesh fixture
        vertices = IM.fromList (zip [0 ..] (samples mesh))
    quiet <- mapM (\hinge -> do (angle, _) <- right (hingeAngle hinge vertices); pure hinge {hingeRest = angle}) (curlHinges fixture)
    result <- right (relaxSurfaceContact defaultSettings quiet (curlContact fixture) mesh)
    finalMesh result `shouldReturn` mesh
    converged result `shouldBe` True
    exhausted <- right (relaxSurfaceContact defaultSettings {iterationLimit = 0} (curlHinges fixture) (curlContact fixture) mesh)
    converged exhausted `shouldBe` False

  it "does not weld coincident corners that have different material identities" $ do
    let triangle = [V3 0 0 0, V3 1 0 0, V3 0 1 0]
        mesh = pairMesh (triangle ++ triangle)
    model <- right (Contact.prepareTriangleContact 1e-6 axis [(0, 1)] mesh)
    rows <- right (Contact.orderedContacts model mesh)
    map contactGap rows `shouldSatisfy` all (== (-1e-6))
    any (any ((> 0.1) . norm . snd) . contactGradient) rows `shouldBe` True

  it "reports invalid local geometry, parameters and unsupported directions" $ do
    let prepare = Contact.prepareTriangleContact 0 axis [(0, 1)]
    Contact.prepareTriangleContact 0 axis [] (Mesh [] []) `shouldBe` Left Contact.EmptyContactMesh
    Contact.prepareTriangleContact (-1) axis [(0, 1)] crossing `shouldBe` Left Contact.InvalidContactClearance
    Contact.prepareTriangleContact (0 / 0) axis [(0, 1)] crossing `shouldBe` Left Contact.InvalidContactClearance
    Contact.prepareTriangleContact 0 (V3 0 0 0) [(0, 1)] crossing `shouldBe` Left Contact.InvalidContactDirection
    Contact.prepareTriangleContact 0 (V3 (1 / 0) 0 0) [(0, 1)] crossing `shouldBe` Left Contact.InvalidContactDirection
    prepare crossing {triangles = [(0, 1, 99), (3, 4, 5)]} `shouldBe` Left (Contact.MissingContactVertex 99)
    prepare (shiftVertex 0 (V3 (0 / 0) 0 0) crossing) `shouldBe` Left (Contact.InvalidContactTriangle 0)
    prepare crossing {samples = [s {sampleMaterial = V2 (0 / 0) 0} | s <- samples crossing]} `shouldBe` Left (Contact.InvalidContactMaterial 0)
    let upright = pairMesh [V3 0 0 0, V3 0 1 0, V3 0 0 1, V3 1 0 0, V3 1 1 0, V3 1 0 1]
    prepare upright `shouldBe` Left (Contact.UncheckableContactPair 0 1)
    checkLocalTriangleContact axis [(0, 999)] crossing `shouldSatisfy` isLeft
    checkLocalTriangleContact axis [(0, 1), (1, 0)] crossing `shouldSatisfy` isLeft
    curledPanel 0 `shouldSatisfy` isLeft
    curledPanel 9 `shouldSatisfy` isLeft

axis :: V3
axis = V3 0 0 1

-- Asymmetric overlapping triangles keep this derivative check away from a
-- clipping branch change. The six material ids are separate even where their
-- current projections overlap.
crossing :: MaterialMesh
crossing = pairMesh [V3 (-2) (-1) 0.1, V3 2 (-1) 0.6, V3 0 2 0.7, V3 (-2) 1 (-0.4), V3 2 1 (-0.2), V3 0 (-2) (-0.9)]

pairMesh :: [V3] -> MaterialMesh
pairMesh points = Mesh (zipWith Sample [V2 0 0, V2 1 0, V2 0 1, V2 2 0, V2 3 0, V2 2 1] points) [(0, 1, 2), (3, 4, 5)]

shiftVertex :: Int -> V3 -> MaterialMesh -> MaterialMesh
shiftVertex i delta mesh = mesh {samples = [if j == i then s {position = position s ^+^ delta} else s | (j, s) <- zip [0 ..] (samples mesh)]}

finalMesh :: Relaxation -> IO MaterialMesh
finalMesh result = case reverse (checkpoints result) of point : _ -> pure (checkpointMesh point); [] -> fail "no final checkpoint"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
