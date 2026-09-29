-- | Which glTF scene the whole-crane viewers are given.
--
-- A folded crane's layers lie on one another at zero distance. The complete
-- scene keeps every layer, so a viewer shown it alone has to choose between
-- coincident triangles, and it does so by depth-buffer rounding, not by the
-- layer order: exactly the paper that should be hidden can win. The visible
-- scene draws only the paper each side exposes, and the same file still
-- carries the complete scene second, so no layer is lost to a reader who
-- wants it (PRD 11, R-11-10).
--
-- The visible scene can refuse, for instance where a panel is further out of
-- plane than its tolerance. Then a pose keeps the complete scene alone, and
-- the reason travels with it rather than being dropped, because a viewer that
-- flickers for a stated reason is a known limit and one that flickers for no
-- stated reason looks like a bug.
module WholeCraneExport (PoseScene (..), poseGlb, sceneName) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Senbazuru.Explain (explain)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface (Surface)
import Senbazuru.Render.Gltf (ExportMode (..), GltfError, renderSurfaceGlb)

-- | The scene a pose's file leads with.
data PoseScene
  = -- | Exposed paper first, every layer second.
    VisibleFirst
  | -- | Every layer only, with the visible scene's refusal.
    CompleteOnly !Text
  deriving stock (Eq, Show)

-- | The visible-paper scene where it exports, else the complete scene alone.
poseGlb :: Text -> Surface material -> Either GltfError (PoseScene, ByteString)
poseGlb title sheet = case renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet of
  Right bytes -> Right (VisibleFirst, bytes)
  Left refusal -> (,) (CompleteOnly (explain refusal)) <$> renderSurfaceGlb defaultBudget CompletePaper (Just title) sheet

-- | How the viewers name the scene they were given.
sceneName :: PoseScene -> Text
sceneName VisibleFirst = "visible"
sceneName (CompleteOnly _) = "complete"
