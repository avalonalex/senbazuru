-- | Reuse the body specimen's material with a new angle-derived position.
-- Grip identities stay at the centre and the two wing attachments; their
-- positions now come from the constructed pose. The old material preferences
-- and inherited directional orders remain the comparison's definition.
-- Rigidly align face zero with the original closed patch so camera changes
-- cannot masquerade as body opening. See docs/notes/body-crease-seed.md.
module BodyCreaseSeed (bodyCreasePattern, bodySeedAlignment, installCreaseSeed) where

import BodyPatch
import Control.Monad (unless)
import CraneSpread
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import Data.Text (Text)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Rigid
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..))
import Senbazuru.Origami.Surface

bodyCreasePattern :: BodyPatch -> Frame
bodyCreasePattern study =
  (surfaceFrame sheet)
    { verticesCoords = [[u, v] | Sample (V2 u v) _ <- surfaceSamples sheet],
      frameClasses = ["creasePattern"],
      frameAttributes = ["2D"],
      edgesFoldAngle = [],
      faceOrders = [],
      frameExtras = mempty
    }
  where
    sheet = spreadSource (patchSpread study)

-- | Production Folding has already checked shared vertices AND achieved
-- angles. This adapter refuses changed material ids or a changed triangulation.
installCreaseSeed :: BodyPatch -> Folded -> Either SpreadError BodyPatch
installCreaseSeed study folded = do
  let fixture = patchSpread study
      expected = refinedMesh (spreadRefined fixture)
      material = bodyCreasePattern study
  unless (verticesCoords (foldedPattern folded) == verticesCoords material && edgesVertices (foldedPattern folded) == edgesVertices material && facesVertices (foldedPattern folded) == facesVertices material) (bad "crease seed changed body material identities")
  transform <- bodySeedAlignment study
  constructed <- checked (surfaceFromFolded folded >>= transformSurface transform)
  refined <- checked (refineSurfaceWithEdges (patchLevel study) constructed)
  let mesh = refinedMesh refined
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples mesh), IM.member i (spreadPins fixture)]
  unless (triangles mesh == triangles expected && map sampleMaterial (samples mesh) == map sampleMaterial (samples expected) && refinedPanels refined == refinedPanels (spreadRefined fixture)) (bad "crease seed changed refined material identities")
  pure study {patchSpread = fixture {spreadMesh = mesh, spreadPins = pins}}

-- | The closed reference panel fixes the contact direction and drawing camera.
bodySeedAlignment :: BodyPatch -> Either SpreadError Rigid
bodySeedAlignment study = do
  let material = bodyCreasePattern study
      original = surfaceSamples (spreadSource (patchSpread study))
  ring <- case facesVertices material of r : _ -> pure (map unVertexId r); _ -> bad "missing fixed reference panel"
  let ps = IM.fromList (zip [0 ..] original)
      point i = maybe (bad "missing reference panel corner") Right (IM.lookup i ps)
  corners <- traverse point ring
  (a, b, c) <- maybe (bad "reference panel needs three noncollinear corners") Right (find noncollinear [(a, b, c) | a <- corners, b <- corners, c <- corners])
  align a b c
  where
    noncollinear (a, b, c) = let to3 (V2 x y) = V3 x y 0 in norm (cross (to3 (sampleMaterial b ^-^ sampleMaterial a)) (to3 (sampleMaterial c ^-^ sampleMaterial a))) > 1e-10
    align a b c = do
      let to3 (V2 x y) = V3 x y 0
          p = to3 (sampleMaterial a)
          q = position a
      (u, v, w) <- axes (to3 (sampleMaterial b) ^-^ p) (to3 (sampleMaterial c) ^-^ p)
      (x, y, z) <- axes (position b ^-^ q) (position c ^-^ q)
      let V3 xx xy xz = x
          V3 yx yy yz = y
          V3 zx zy zz = z
          matrix = Mat3 (xx *^ u ^+^ yx *^ v ^+^ zx *^ w) (xy *^ u ^+^ yy *^ v ^+^ zy *^ w) (xz *^ u ^+^ yz *^ v ^+^ zz *^ w)
      pure (Rigid matrix (q ^-^ matApply matrix p))
    axes a b = do
      u <- maybe (bad "invalid reference direction") Right (normalize a)
      w <- maybe (bad "invalid reference normal") Right (normalize (cross a b))
      pure (u, cross w u, w)

bad :: Text -> Either SpreadError a
bad = Left . SpreadError

checked :: (Explain e) => Either e a -> Either SpreadError a
checked = first (SpreadError . explain)
