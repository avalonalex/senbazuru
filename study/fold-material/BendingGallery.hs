-- | Generate recorded equilibrium attempts, never interpolated folding motion.
-- Geometry and measurements are computed here; the HTML only selects and views
-- the saved meshes. The unit-square packet assumptions live in FoldContact.
module BendingGallery (writeBendingStudy) where

import ContactDiscovery qualified as Discovery
import ContactExample
import Control.Monad (when)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes)
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldContact
import FoldMaterial
import FoldRelaxation
import PanelContact
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Crease (..))
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), FoldFile (..), Frame (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface qualified as Paper
import StudyCase
import SurfaceContact qualified as Contact
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeBendingStudy :: FilePath -> IO ()
writeBendingStudy destination = do
  createDirectoryIfMissing True destination
  packets <-
    mapM
      generate
      [ ("Single fold", Single, defaultBending, defaultPacketRestAngles {firstRestAngle = 150 * pi / 180}),
        ("Double fold · softer panels", Double, defaultBending {panelStiffness = 0.2}, defaultPacketRestAngles),
        ("Double fold · stiffer panels", Double, defaultBending, defaultPacketRestAngles)
      ]
  surfaces <-
    mapM
      generateSurface
      [ ("Diagonal fold", "examples/diagonal-cp.fold", [0, 0, 0, 0, 60], [(EdgeId 4, 120)], [("base", V2 0.2 0.2), ("flap", V2 0.8 0.8)], [("base", "flap")]),
        ("Kite base", "examples/kite-base.fold", [0, 0, 0, 0, 0, 0, 75, 110], [(EdgeId 6, 150), (EdgeId 7, 165)], [("base", V2 0.6 0.6), ("right flap", V2 0.8 0.1), ("left flap", V2 0.1 0.8)], [("base", "right flap"), ("base", "left flap")])
      ]
  contacts <- mapM generateContact [False, True]
  let document = encode (object ["runs" .= (packets ++ surfaces ++ contacts), "lengthTolerance" .= lengthTolerance settings, "contactTolerance" .= contactTolerance])
  BL.writeFile (destination </> "bending.json") document
  template <- TIO.readFile "study/fold-material/bending.html"
  TIO.writeFile (destination </> "bending.html") (T.replace "/*BENDING_DATA*/null" (TE.decodeUtf8 (BL.toStrict document)) template)
  putStrLn ("Wrote bending.html and bending.json to " ++ destination)
  where
    settings = Settings 100 1e-5
    generate (title, which, bending, targets) = do
      let mesh = sharpMesh 4 which
      hinges <- checked (buildHinges bending targets which mesh)
      result <- checked (relaxBending settings bending targets which mesh)
      states <- mapM (snapshot hinges (Packet which)) (checkpoints result)
      putStrLn ((title :: String) ++ ": equilibrium checks " ++ show (converged result))
      pure (object ["kind" .= ("packet" :: String), "title" .= title, "converged" .= converged result, "firstTarget" .= degrees (firstRestAngle targets), "secondTarget" .= degrees (secondRestAngle targets), "panelStiffness" .= panelStiffness bending, "creaseStiffness" .= creaseStiffness bending, "states" .= states])

-- The fixture controls are explicit in their source edge numbering. They are
-- resolved on the cut surface before the mechanics adapter is called.
generateSurface :: (String, FilePath, [Double], [(EdgeId, Double)], [(T.Text, V2)], [(T.Text, T.Text)]) -> IO Value
generateSurface (title, sourcePath, startingAngles, targetDegrees, tags, orders) = do
  source <- loadFoldFile sourcePath >>= checked
  let spec = CaseSpec "bending" (T.pack title) sourcePath "" [] Nothing (Just (ContactSpec (V3 0 0 1) [PanelTag name point | (name, point) <- tags] orders))
  pose <- checked (buildCasePose 0 spec (keyFrame source) (PoseSpec "Starting shape" startingAngles))
  -- These two prepared fixtures are not cut into different edge ids. Refuse
  -- an accidental numbering change instead of applying controls to other folds.
  when (edgesVertices (Paper.surfaceFrame (poseSurface pose)) /= edgesVertices (keyFrame source)) $
    die "bending gallery fixture edge ids changed during cutting; resolve its controls on the cut surface"
  let targets = M.fromList [(eid, angle * pi / 180) | (eid, angle) <- targetDegrees]
  (refined, hinges) <- checked (buildSurfaceHinges defaultBending 2 (poseSurface pose) targets)
  let mesh = Paper.refinedMesh refined
  result <- checked (relaxHinges defaultSettings hinges mesh)
  which <- surfaceCase (poseSurface pose) refined
  states <- mapM (snapshot hinges which) (checkpoints result)
  putStrLn (title ++ ": equilibrium checks " ++ show (converged result))
  pure (object ["kind" .= ("surface" :: String), "title" .= title, "source" .= sourcePath, "converged" .= converged result, "panelStiffness" .= panelStiffness defaultBending, "creaseStiffness" .= creaseStiffness defaultBending, "states" .= states])

-- Both results use identical initial material and crease preferences. The
-- baseline is the unconstrained ENDPOINT, not the corrected run's first iterate.
generateContact :: Bool -> IO Value
generateContact discover = do
  fixture <- checked (if discover then opposingFlapsAt 1 145 125 else opposingFlaps 1)
  let refined = exampleRefined fixture
      mesh = Paper.refinedMesh refined
      hinges = exampleHinges fixture
  free <- checked (relaxHinges defaultSettings hinges mesh)
  let axis = V3 0 0 1
  reference <- if discover then Just <$> checked (Discovery.discoverReference (exampleClearance fixture) axis (Paper.refinedPanels refined) mesh) else pure Nothing
  corrected <- checked $ case reference of
    Nothing -> relaxSurfaceContact defaultSettings hinges (exampleContact fixture) mesh
    Just learned -> relaxDiscoveredContact defaultSettings hinges learned mesh
  surface <- case reference of
    Nothing -> pure (exampleSurface fixture)
    Just learned -> checked (Paper.withLayerRequirements axis (Discovery.referenceOrders learned) (exampleSurface fixture))
  which <- surfaceCase surface refined
  baseline <- case reverse (checkpoints free) of
    point : _ -> snapshot hinges which point
    [] -> die "contact comparison needs an unconstrained endpoint"
  states <- mapM (snapshot hinges which) (checkpoints corrected)
  discovery <- case reference of
    Nothing -> pure Nothing
    Just learned -> do
      counts <-
        mapM
          ( \point -> do
              candidates <- checked (Contact.overlapCandidates axis (Paper.refinedPanels refined) (checkpointMesh point))
              pure (object ["iteration" .= completedIterations point, "trianglePairs" .= length candidates, "panelPairs" .= S.size (S.fromList (map Contact.candidatePanels candidates))])
          )
          (checkpoints corrected)
      pure (Just (object ["referenceTrianglePairs" .= length (Discovery.referenceCandidates learned), "orders" .= [[unFaceId a, unFaceId b] | (a, b) <- Discovery.referenceOrders learned], "candidateCounts" .= counts]))
  putStrLn ((if discover then "Discovered opposing flaps" else "Opposing flaps") ++ ": free equilibrium " ++ show (converged free) ++ "; corrected equilibrium " ++ show (converged corrected))
  pure
    ( object
        [ "kind" .= (if discover then "discovery" else "contact" :: String),
          "title" .= (if discover then "Opposing flaps · discovered contact" else "Opposing flaps · contact correction" :: String),
          "discovery" .= discovery,
          "converged" .= converged corrected,
          "baselineConverged" .= converged free,
          "baseline" .= baseline,
          "numericalClearance" .= exampleClearance fixture,
          "panelStiffness" .= panelStiffness defaultBending,
          "creaseStiffness" .= creaseStiffness defaultBending,
          "states" .= states
        ]
    )

surfaceCase :: Paper.Surface V2 -> Paper.RefinedSurface -> IO SnapshotCase
surfaceCase surface refined = do
  features <- checked (Paper.surfaceFeatures surface)
  let visible = S.fromList [creaseId edge | (edge, _) <- features]
      segments = [segment | (eid, segment) <- Paper.refinedEdges refined, S.member eid visible]
  (axis, requirements) <- maybe (die "surface bending example needs explicit panel order") pure (Paper.surfaceLayerRequirements surface)
  pure (SurfaceCase (Paper.refinedPanels refined) segments axis requirements)

data SnapshotCase = Packet FoldCase | SurfaceCase [FaceId] [(Int, Int)] V3 [(FaceId, FaceId)]

snapshot :: [Hinge] -> SnapshotCase -> Checkpoint -> IO Value
snapshot hinges which checkpoint = do
  let mesh = checkpointMesh checkpoint
      vertices = IM.fromList (zip [0 ..] (samples mesh))
      coords (V3 x y z) = [x, y, z]
      triple (a, b, c) = [a, b, c]
      measured = [principalStrains t | t <- resolvedTriangles mesh]
      strains = catMaybes measured
  (panels, lines', contactFields) <- case which of
    Packet packet -> do
      let contacts = packetCheck packet mesh
          feature a b = any (\coordinate -> any (\t -> abs (coordinate a - t) < 1e-10 && abs (coordinate b - t) < 1e-10) [0, 1]) [materialU, materialV]
          creaseSegments = [ordered a b | h <- hinges, hingeRole h /= PanelBend, let (a, b, _, _) = hingeVertices h]
          boundary = [ordered a b | (a, b) <- meshEdges mesh, Just pa <- [IM.lookup a vertices], Just pb <- [IM.lookup b vertices], feature pa pb]
      pure
        ( [packetLayer packet ((materialU a + materialU b + materialU c) / 3) ((materialV a + materialV b + materialV c) / 3) | (a, b, c) <- resolvedTriangles mesh],
          S.toList (S.fromList (boundary ++ creaseSegments)),
          ["maxOrderViolation" .= maxOrderViolation contacts, "violatingPairs" .= violatingPairs contacts, "uncheckedTriangles" .= uncheckedTriangles contacts, "packetContact" .= True]
        )
    SurfaceCase owners segments axis requirements -> do
      contacts <- checked (checkTriangleContact axis requirements owners mesh)
      pure (map unFaceId owners, segments, ["contact" .= contacts, "packetContact" .= False, "orderDirection" .= coords axis, "panelOrders" .= [[unFaceId a, unFaceId b] | (a, b) <- requirements]])
  (crease, panel) <- checked (bendingEnergy hinges mesh)
  let angleValue hinge = do
        (angle, _) <- checked (hingeAngle hinge vertices)
        let (a, b, c, d) = hingeVertices hinge
            eid = case hingeRole hinge of SurfaceCrease source -> Just (unEdgeId source); _ -> Nothing
            role = case hingeRole hinge of SurfaceCrease _ -> "SurfaceCrease"; other -> show other
        pure (object ["vertices" .= [a, b, c, d], "role" .= role, "sourceEdge" .= eid, "angle" .= degrees angle, "rest" .= degrees (hingeRest hinge)])
  angles <- mapM angleValue hinges
  pure
    ( object
        ( [ "iteration" .= completedIterations checkpoint,
            "positions" .= map (coords . position) (samples mesh),
            "material" .= map (\s -> [materialU s, materialV s]) (samples mesh),
            "triangles" .= map triple (triangles mesh),
            "panels" .= panels,
            "featureEdges" .= [[a, b] | (a, b) <- lines'],
            "angles" .= angles,
            "creaseEnergy" .= crease,
            "panelEnergy" .= panel,
            "lengthError" .= checkpointError checkpoint,
            "minPrincipalStrain" .= minimum (0 : map fst strains),
            "maxPrincipalStrain" .= maximum (0 : map snd strains),
            "components" .= componentCount mesh,
            "areaRatio" .= areaRatio mesh
          ]
            ++ contactFields
        )
    )
  where
    ordered a b = (min a b, max a b)

degrees :: Double -> Double
degrees angle = angle * 180 / pi

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
