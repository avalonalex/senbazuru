-- | The glTF file a whole-crane viewer is given: visible paper first, every
-- layer second.
--
-- A folded crane's layers lie on one another at exactly the same depth. A
-- viewer shown every layer then shows *z-fighting*, a shimmer of the
-- coincident faces decided by its depth buffer rather than by the *layer
-- order* (both in docs/glossary.md), so paper that should be hidden can win:
-- drawn front red and underside blue, the closed crane showed 83-95% underside
-- that way. PRD 11 (R-11-10) says a gallery viewer loads the visible-paper
-- scene, which draws only the paper each side exposes, or gives coincident
-- layers a depth bias; never the complete scene alone. The file keeps the
-- complete scene second, so no layer is lost to a reader who wants it.
--
-- There is deliberately no fallback to the complete scene alone. Every face
-- here is one triangle of the mesh, so the visible scene can refuse only
-- where it cannot order overlapping faces that share a plane: exactly where
-- layers coincide, and so exactly where a complete-only file would shimmer.
-- A refusal therefore stops the gallery with its reason, and the missing
-- layer order gets supplied rather than the shimmer shipped.
--
-- Each file also records how its pose was made, as the geometry level of a
-- fidelity record ("Senbazuru.Render.Fidelity"): a pose placed rather than
-- folded says @as prescribed@, a shape sketch, where anyone who opens the
-- file can read it (PRD 11, R-11-2).
--
-- It is a module of its own so that the test suite, which does not compile
-- the gallery, can check the choice.
module WholeCraneExport (viewerGlb) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface (Surface)
import Senbazuru.Render.Fidelity (Geometry)
import Senbazuru.Render.Gltf (ExportMode (..), GlbOptions (..), GltfError, plainGlb, renderSurfaceGlbWith)

-- | A pose's file for the viewers: the visible-paper scene, then the
-- complete one, recording how the pose was made.
viewerGlb :: Geometry -> Text -> Surface material -> Either GltfError ByteString
viewerGlb geometry title = renderSurfaceGlbWith (plainGlb VisiblePaper) {glbGeometry = Just geometry} defaultBudget (Just title)
