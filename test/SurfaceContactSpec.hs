module SurfaceContactSpec (spec) where

import ContactExample
import Control.Monad (forM_)
import Data.IntMap.Strict qualified as IM
import Data.List (sort)
import FoldBending
import FoldContact (ContactRow (..), contactTolerance)
import FoldMaterial (componentCount)
import FoldRelaxation
import PanelContact
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import Test.Hspec

spec :: Spec
spec = describe "open-flap contact correction" $ do
  it "stops opposing flaps from crossing without changing their material" $ do
    fixture <- right (opposingFlaps 1)
    let refined = exampleRefined fixture
        mesh = refinedMesh refined
        hinges = exampleHinges fixture
        model = exampleContact fixture
    free <- right (relaxHinges defaultSettings hinges mesh)
    freeMesh <- finalMesh free
    corrected <- right (relaxSurfaceContact defaultSettings hinges model mesh)
    final <- finalMesh corrected
    (axis, requirements) <- maybe (fail "missing orders") pure (surfaceLayerRequirements (exampleSurface fixture))
    let report m = right (checkTriangleContact axis requirements (refinedPanels refined) m)
    initialReport <- report mesh
    freeReport <- report freeMesh
    correctedReport <- report final
    contactPassed initialReport `shouldBe` True
    converged free `shouldBe` True
    crossingPanels freeReport `shouldSatisfy` (not . null)
    reversedOrders freeReport `shouldSatisfy` (not . null)
    converged corrected `shouldBe` True
    contactPassed correctedReport `shouldBe` True
    checkedPanelPairs correctedReport `shouldBe` 276
    maxLengthError final `shouldSatisfy` (<= lengthTolerance defaultSettings)
    rows <- right (Contact.orderedContacts model final)
    minimum (0 : map contactGap rows) `shouldSatisfy` (>= negate contactTolerance)
    forM_ (checkpoints corrected) $ \point -> do
      let current = checkpointMesh point
      map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples mesh)
      triangles current `shouldBe` triangles mesh
      componentCount current `shouldBe` 1
    -- The constraints must actually change the achieved crease angles, rather
    -- than hide the crossing or report the requested targets as measurements.
    errors <- mapM (\h -> abs . angleError (hingeRest h) . fst <$> right (hingeAngle h (IM.fromList (zip [0 ..] (samples final))))) [h | h <- hinges, hingeRole h /= PanelBend]
    maximum (0 : errors) `shouldSatisfy` (> 5 * pi / 180)

  it "does not call an exhausted contact solve converged" $ do
    fixture <- right (opposingFlaps 1)
    result <- right (relaxSurfaceContact defaultSettings {iterationLimit = 1} (exampleHinges fixture) (exampleContact fixture) (refinedMesh (exampleRefined fixture)))
    converged result `shouldBe` False

  forM_ [("vertex/face", contained), ("moving edge/edge", crossing)] $ \(name, mesh) ->
    it ("differentiates " ++ name ++ " contacts, including horizontal movement") $ do
      model <- prepare 0 mesh
      rows <- right (Contact.orderedContacts model mesh)
      let energy m = sum . map (\r -> min 0 (contactGap r) ** 2 / 2) <$> right (Contact.orderedContacts model m)
          analytic = IM.fromListWith (^+^) [(i, contactGap r *^ g) | r <- rows, contactGap r < 0, (i, g) <- contactGradient r]
      length rows `shouldSatisfy` (>= 3)
      forM_ [0 .. length (samples mesh) - 1] $ \i ->
        forM_ [V3 1 0 0, V3 0 1 0, V3 0 0 1] $ \axis -> do
          plus <- energy (shiftVertex i (1e-6 *^ axis) mesh)
          minus <- energy (shiftVertex i ((-1e-6) *^ axis) mesh)
          abs ((plus - minus) / 2e-6 - dot axis (IM.findWithDefault (V3 0 0 0) i analytic)) `shouldSatisfy` (< 1e-7)
      -- Whole-sheet translation cannot change a contact residual.
      forM_ rows $ \row -> norm (foldr ((^+^) . snd) (V3 0 0 0) (contactGradient row)) `shouldSatisfy` (< 1e-12)
      report <- right (checkTriangleContact (V3 0 0 1) orders owners mesh)
      let independent = maximum (0 : [gap | (_, _, gap) <- reversedOrders report])
      abs (independent + minimum (0 : map contactGap rows)) `shouldSatisfy` (< 1e-12)

  it "retains both heights of an upright flap with coincident projected corners" $ do
    let mesh = pairMesh [V3 (-2) (-2) 0, V3 2 (-2) 0, V3 0 3 0, V3 0 0 (-0.4), V3 0 0 0.6, V3 0 1 0.6]
    rows <- prepare 0 mesh >>= \model -> right (Contact.orderedContacts model mesh)
    minimum (map contactGap rows) `shouldBe` (-0.4)
    maximum (map contactGap rows) `shouldBe` 0.6
    model <- right (Contact.prepareContact 0 (V3 0 0 1) [(FaceId 1, FaceId 0)] owners mesh)
    reversed <- right (Contact.orderedContacts model mesh)
    minimum (map contactGap reversed) `shouldBe` (-0.6)

  it "gives the same gaps when the sheet and its material direction rotate together" $ do
    let rotate (V3 x y z) = V3 z x y
        moved = mapPositions (\p -> rotate p ^+^ V3 3 (-2) 5) crossing
    original <- prepare 0 crossing >>= \model -> right (Contact.orderedContacts model crossing)
    model <- right (Contact.prepareContact 0 (rotate (V3 0 0 1)) orders owners moved)
    rotated <- right (Contact.orderedContacts model moved)
    length original `shouldBe` length rotated
    maximum (0 : zipWith (\a b -> abs (a - b)) (sort (map contactGap original)) (sort (map contactGap rotated))) `shouldSatisfy` (< 1e-12)

  it "applies clearance to separate material panels without welding coincident positions" $ do
    let mesh = pairMesh (replicateCorners ++ replicateCorners)
        replicateCorners = [V3 0 0 0, V3 1 0 0, V3 0 1 0]
    rows <- prepare 1e-6 mesh >>= \model -> right (Contact.orderedContacts model mesh)
    map contactGap rows `shouldSatisfy` all (== (-1e-6))
    -- Coincident geometric corners have distinct material ids and opposite
    -- contributions. They must not cancel as though they were one vertex.
    any (any ((> 0.1) . norm . snd) . contactGradient) rows `shouldBe` True

  it "keeps zero clearance at joined source panels, even after subdivision" $ do
    fixture <- right (opposingFlaps 1)
    let refined = exampleRefined fixture
        mesh = refinedMesh refined
    (axis, requirements) <- maybe (fail "missing orders") pure (surfaceLayerRequirements (exampleSurface fixture))
    model <- right (Contact.prepareContact 1e-3 axis requirements (refinedPanels refined) mesh)
    rows <- right (Contact.orderedContacts model mesh)
    minimum (0 : map contactGap rows) `shouldSatisfy` (>= (-1e-12))

  it "leaves separated flaps alone when their crease preferences are already met" $ do
    fixture <- right (opposingFlaps 1)
    let mesh = refinedMesh (exampleRefined fixture)
    hinges <- mapM (\h -> do (angle, _) <- right (hingeAngle h (IM.fromList (zip [0 ..] (samples mesh)))); pure h {hingeRest = angle}) (exampleHinges fixture)
    result <- right (relaxSurfaceContact defaultSettings hinges (exampleContact fixture) mesh)
    final <- finalMesh result
    converged result `shouldBe` True
    final `shouldBe` mesh

  it "refuses an order when both triangles stand parallel to its direction" $ do
    let upright = pairMesh [V3 0 0 0, V3 0 1 0, V3 0 0 1, V3 1 0 0, V3 1 1 0, V3 1 0 1]
    Contact.prepareContact 0 (V3 0 0 1) orders owners upright `shouldBe` Left (Contact.UncheckableContactPair 0 1)

  it "rejects invalid directions, clearances, ownership and cyclic orders" $ do
    Contact.prepareContact 0 (V3 0 0 0) orders owners crossing `shouldBe` Left Contact.InvalidContactDirection
    Contact.prepareContact 0 (V3 (0 / 0) 0 1) orders owners crossing `shouldBe` Left Contact.InvalidContactDirection
    Contact.prepareContact (-1) (V3 0 0 1) orders owners crossing `shouldBe` Left Contact.InvalidContactClearance
    Contact.prepareContact (1 / 0) (V3 0 0 1) orders owners crossing `shouldBe` Left Contact.InvalidContactClearance
    Contact.prepareContact 0 (V3 0 0 1) orders [] crossing `shouldBe` Left Contact.InvalidContactOwners
    Contact.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 9)] owners crossing `shouldBe` Left (Contact.UnknownContactPanel (FaceId 9))
    Contact.prepareContact 0 (V3 0 0 1) (orders ++ [(FaceId 1, FaceId 0)]) owners crossing `shouldBe` Left Contact.CyclicContactOrder

  it "refuses missing vertices, degenerate triangles and nonfinite positions" $ do
    Contact.prepareContact 0 (V3 0 0 1) orders owners crossing {triangles = [(0, 1, 99), (3, 4, 5)]} `shouldBe` Left (Contact.MissingContactVertex 99)
    Contact.prepareContact 0 (V3 0 0 1) orders owners crossing {triangles = [(0, 0, 2), (3, 4, 5)]} `shouldBe` Left (Contact.InvalidContactTriangle 0)
    Contact.prepareContact 0 (V3 0 0 1) orders owners (shiftVertex 0 (V3 (1 / 0) 0 0) crossing) `shouldBe` Left (Contact.InvalidContactTriangle 0)

  it "refuses changed connectivity or original-sheet coordinates after preparation" $ do
    model <- prepare 0 crossing
    Contact.orderedContacts model crossing {triangles = reverse (triangles crossing)} `shouldBe` Left Contact.ChangedContactMaterial
    Contact.orderedContacts model crossing {samples = [s {sampleMaterial = V2 7 8} | s <- samples crossing]} `shouldBe` Left Contact.ChangedContactMaterial

owners :: [FaceId]
owners = [FaceId 0, FaceId 1]

orders :: [(FaceId, FaceId)]
orders = [(FaceId 0, FaceId 1)]

prepare :: Double -> MaterialMesh -> IO Contact.OrderedContact
prepare clearance = right . Contact.prepareContact clearance (V3 0 0 1) orders owners

-- These two triangles have six distinct material ids. Repeated original
-- coordinates do not merge them: contact preparation must preserve identity.
pairMesh :: [V3] -> MaterialMesh
pairMesh points = Mesh (zipWith Sample (cycle [V2 0 0, V2 1 0, V2 0 1]) points) [(0, 1, 2), (3, 4, 5)]

contained, crossing :: MaterialMesh
contained = pairMesh [V3 (-2) (-2) 0.1, V3 2 (-2) 0.3, V3 0 3 0.2, V3 (-0.3) 0 (-0.4), V3 0.3 0 (-0.2), V3 0 0.6 (-0.3)]
crossing = pairMesh [V3 (-2) (-1) 0.1, V3 2 (-1) 0.6, V3 0 2 0.7, V3 (-2) 1 (-0.4), V3 2 1 (-0.2), V3 0 (-2) (-0.9)]

mapPositions :: (V3 -> V3) -> MaterialMesh -> MaterialMesh
mapPositions f mesh = mesh {samples = [s {position = f (position s)} | s <- samples mesh]}

shiftVertex :: Int -> V3 -> MaterialMesh -> MaterialMesh
shiftVertex i delta mesh = mesh {samples = [if j == i then s {position = position s ^+^ delta} else s | (j, s) <- zip [0 ..] (samples mesh)]}

finalMesh :: Relaxation -> IO MaterialMesh
finalMesh result = case reverse (checkpoints result) of
  point : _ -> pure (checkpointMesh point)
  [] -> fail "no final checkpoint"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
