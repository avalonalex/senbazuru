-- | Generate recorded equilibrium attempts, never interpolated folding motion.
-- Geometry and measurements are computed here; the HTML only selects and views
-- the saved meshes. The unit-square packet assumptions live in FoldContact.
module BendingGallery (writeBendingStudy) where

import ContactDiscovery qualified as Discovery
import ContactExample
import Control.Monad (when)
import CorrectionExample
import CorrectionSweep qualified as Motion
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
import HingeSweep qualified as Sweep
import LocalContactDiscovery qualified as Local
import PanelContact
import SelfContactExample
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
  contacts <- mapM generateContact [DeclaredStart, ReferenceStart, ApproachStart]
  selfContact <- generateSelfContact
  localDiscovery <- generateLocalDiscovery
  localHistory <- generateLocalHistory
  corrections <- generateCorrectionStudy
  let document = encode (object ["runs" .= (packets ++ surfaces ++ contacts ++ [selfContact, localDiscovery, localHistory, corrections]), "lengthTolerance" .= lengthTolerance settings, "contactTolerance" .= contactTolerance])
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
data ContactStart = DeclaredStart | ReferenceStart | ApproachStart
  deriving stock (Eq)

generateContact :: ContactStart -> IO Value
generateContact mode = do
  approach <- if mode == ApproachStart then checked (opposingApproach 1) else pure []
  fixture <- case reverse approach of
    pose : _ -> pure (approachExample pose)
    [] -> checked (if mode == ReferenceStart then opposingFlapsAt 1 145 125 else opposingFlaps 1)
  let refined = exampleRefined fixture
      mesh = Paper.refinedMesh refined
      hinges = exampleHinges fixture
  free <- checked (relaxHinges defaultSettings hinges mesh)
  let axis = V3 0 0 1
  reference <- case reverse approach of
    pose : _ -> pure (Just (approachHistory pose))
    [] -> if mode == ReferenceStart then Just <$> checked (Discovery.discoverReference (exampleClearance fixture) axis (Paper.refinedPanels refined) mesh) else pure Nothing
  approachStates <- mapM approachSnapshot approach
  probe <- case approach of
    firstPose : _ -> Just <$> sweepProbe firstPose
    [] -> pure Nothing
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
  let (kind, title) = case mode of
        DeclaredStart -> ("contact", "Opposing flaps · contact correction")
        ReferenceStart -> ("discovery", "Opposing flaps · discovered contact")
        ApproachStart -> ("history", "Opposing flaps · first contact")
  putStrLn (title ++ ": free equilibrium " ++ show (converged free) ++ "; corrected equilibrium " ++ show (converged corrected))
  pure
    ( object
        [ "kind" .= (kind :: String),
          "title" .= title,
          "approach" .= approachStates,
          "motionProbe" .= probe,
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

-- One uncreased panel: the contact ids name local triangles, not new panels.
generateSelfContact :: IO Value
generateSelfContact = do
  fixture <- checked (curledPanel 8)
  let mesh = curlMesh fixture
      hinges = curlHinges fixture
      which = LocalCase (curlOwners fixture) (curlBoundary fixture) (V3 0 0 1) (curlPairs fixture) (curlContact fixture)
  free <- checked (relaxHinges defaultSettings hinges mesh)
  corrected <- checked (relaxSurfaceContact defaultSettings hinges (curlContact fixture) mesh)
  baseline <- case reverse (checkpoints free) of
    point : _ -> snapshot hinges which point
    [] -> die "curled panel comparison needs an unconstrained endpoint"
  states <- mapM (snapshot hinges which) (checkpoints corrected)
  putStrLn ("Curled panel: free equilibrium " ++ show (converged free) ++ "; corrected equilibrium " ++ show (converged corrected))
  pure (object ["kind" .= ("selfcontact" :: String), "title" .= ("Curled panel · self-contact" :: String), "converged" .= converged corrected, "baselineConverged" .= converged free, "baseline" .= baseline, "states" .= states, "numericalClearance" .= curlClearance fixture, "triangleOrders" .= curlPairs fixture, "sourcePanels" .= (1 :: Int), "startingBend" .= (40 :: Int), "controlTarget" .= (60 :: Int), "controlStrength" .= (4 :: Int)])

-- A tighter separated curl lets near-contact discovery see the returning end.
-- No authored fixture pairs or contact model enter this correction.
generateLocalDiscovery :: IO Value
generateLocalDiscovery = do
  fixture <- checked (curledPanelAt 8 44.5)
  let mesh = curlMesh fixture
      hinges = curlHinges fixture
      axis = V3 (-3) 0 1
      searchDistance = 0.03
  reference <- checked (Local.discoverLocalReference (curlClearance fixture) searchDistance axis mesh)
  let orders = Local.localReferenceOrders reference
  model <- checked (Contact.prepareTriangleContact (curlClearance fixture) axis orders mesh)
  let which = LocalCase (curlOwners fixture) (curlBoundary fixture) axis orders model
  free <- checked (relaxHinges defaultSettings hinges mesh)
  corrected <- checked (relaxLocalContact defaultSettings hinges reference mesh)
  baseline <- case reverse (checkpoints free) of
    point : _ -> snapshot hinges which point
    [] -> die "local discovery comparison needs an unconstrained endpoint"
  states <- mapM (snapshot hinges which) (checkpoints corrected)
  let candidate row = object ["triangles" .= Contact.localTriangles row, "gapRange" .= Contact.localGapRange row]
  putStrLn ("Curled panel discovery: " ++ show (length orders) ++ " relationships; equilibrium " ++ show (converged corrected))
  pure (object ["kind" .= ("localdiscovery" :: String), "title" .= ("Curled panel · discovered contact" :: String), "converged" .= converged corrected, "baselineConverged" .= converged free, "baseline" .= baseline, "states" .= states, "numericalClearance" .= curlClearance fixture, "searchDistance" .= searchDistance, "referenceCandidates" .= map candidate (Local.localReferenceCandidates reference), "triangleOrders" .= orders, "sourcePanels" .= (1 :: Int), "startingBend" .= (44.5 :: Double), "controlTarget" .= (60 :: Int), "controlStrength" .= (4 :: Int)])

-- Compare the stalled frozen reference against growth on the same finer strip.
-- Each checkpoint uses only relationships learned by its own iteration. Audit
-- poses are exported too, so the positive gaps can be inspected independently.
generateLocalHistory :: IO Value
generateLocalHistory = do
  fixture <- checked (curledPanelAt 16 22.25)
  let mesh = curlMesh fixture
      hinges = curlHinges fixture
      axis = V3 (-3) 0 1
      clearance = curlClearance fixture
      searchDistance = 0.03
  reference <- checked (Local.discoverLocalReference clearance searchDistance axis mesh)
  frozen <- checked (relaxLocalContact defaultSettings hinges reference mesh)
  (corrected, learned) <- checked (relaxLocalHistory defaultSettings hinges reference mesh)
  let initialOrders = Local.localReferenceOrders reference
      events = Local.localReferenceEncounters learned
      atIteration count = S.toAscList (S.fromList (initialOrders ++ concatMap Local.encounterOrders (filter ((<= count) . Local.encounterIteration) events)))
      capture orders point = do
        model <- checked (Contact.prepareTriangleContact clearance axis orders (checkpointMesh point))
        snapshot hinges (LocalCase (curlOwners fixture) (curlBoundary fixture) axis orders model) point
      candidate row = object ["triangles" .= Contact.localTriangles row, "gapRange" .= Contact.localGapRange row]
      observation event = do
        let count = Local.encounterIteration event
            current = Local.encounterMesh event
        state <- capture (atIteration count) (Checkpoint count current (maxLengthError current))
        pure (object ["iteration" .= count, "newOrders" .= Local.encounterOrders event, "candidates" .= map candidate (Local.encounterCandidates event), "state" .= state])
  baseline <- case reverse (checkpoints frozen) of
    point : _ -> capture initialOrders point
    [] -> die "local history comparison needs a frozen-reference endpoint"
  states <- mapM (\point -> capture (atIteration (completedIterations point)) point) (checkpoints corrected)
  encounters <- mapM observation events
  putStrLn ("Curled panel history: " ++ show (length initialOrders) ++ " initial relationships, " ++ show (length (Local.localReferenceOrders learned)) ++ " final; frozen equilibrium " ++ show (converged frozen) ++ "; growing equilibrium " ++ show (converged corrected))
  pure (object ["kind" .= ("localhistory" :: String), "title" .= ("Curled panel · growing contact history" :: String), "converged" .= converged corrected, "baselineConverged" .= converged frozen, "baseline" .= baseline, "states" .= states, "encounters" .= encounters, "initialOrders" .= initialOrders, "triangleOrders" .= Local.localReferenceOrders learned, "numericalClearance" .= clearance, "searchDistance" .= searchDistance, "sourcePanels" .= (1 :: Int), "startingBend" .= (22.25 :: Double), "controlTarget" .= (30 :: Int), "controlStrength" .= (4 :: Int)])

-- One deliberately invalid shortcut and two solver controls. Report the
-- measured outcome: near-contact line searches can differ across platforms.
generateCorrectionStudy :: IO Value
generateCorrectionStudy = do
  let (start, finish) = crossingCorrection
      owners = [FaceId 0, FaceId 1]
      boundary = [(0, 1), (1, 3), (3, 2), (2, 0), (1, 2)]
      capture mesh = do
        model <- checked (Contact.prepareTriangleContact 0 (V3 0 0 1) [] mesh)
        snapshot [] (LocalCase owners boundary (V3 0 0 1) [] model) (Checkpoint 0 mesh (maxLengthError mesh))
  motion <- checked (Motion.prepareCorrection start finish)
  report <- checked (Motion.checkCorrection Motion.defaultCorrectionSettings motion)
  progress <- case Motion.correctionOutcome report of
    Motion.CorrectionCollision t _ | t > 0 && t < 1 -> pure t
    _ -> die "correction shortcut needs an interior collision witness"
  middle <- checked (Motion.correctionMeshAt motion progress)
  a <- capture start
  b <- capture finish
  witness <- capture middle
  closingFixture <- checked (curledPanelAt 16 22.25)
  openingFixture <- checked openingStrip
  curl <- checkedCurl Nothing False closingFixture
  opened <- checkedCurl Nothing True openingFixture
  barrierCurl <- checkedCurl (Just 0.001) False closingFixture
  barrierOpened <- checkedCurl (Just 0.001) True openingFixture
  let explanation = "The square is folded 120 degrees to opposite sides of its diagonal at the two endpoints. Both keep material lengths and pass static contact checks. The straight numerical shortcut sends the lifted corner through the base halfway across. Unfolding and refolding is a different path; these samples are not folding instructions."
      probe label right caption = object ["title" .= (label :: String), "left" .= a, "right" .= right, "leftCaption" .= ("Valid starting pose" :: String), "rightCaption" .= (caption :: String), "status" .= ("rejected" :: String), "description" .= (explanation :: String), "motion" .= correctionValue report, "motions" .= ([] :: [Value])]
  pure (object ["kind" .= ("correction" :: String), "title" .= ("Contact between numerical poses" :: String), "views" .= [probe "Shortcut · clear endpoints" b "Valid endpoint · unsafe route", probe "Shortcut · interior collision" witness "Rejected correction · halfway", curl, opened, barrierCurl, barrierOpened]])
  where
    checkedCurl barrier isOpening fixture = do
      let mesh = curlMesh fixture
          hinges = curlHinges fixture
          axis = V3 (-3) 0 1
          clearance = curlClearance fixture
      reference <- checked (Local.discoverLocalReference clearance 0.03 axis mesh)
      guarded <- checked (case barrier of Nothing -> relaxSweptLocalHistory defaultSettings Motion.defaultCorrectionSettings hinges reference mesh; Just activation -> relaxBarrierLocalHistory defaultSettings Motion.defaultCorrectionSettings activation hinges reference mesh)
      (baseline, baselineReference) <-
        if isOpening
          then pure (Relaxation [Checkpoint 0 mesh (maxLengthError mesh)] False, reference)
          else case barrier of
            Nothing -> checked (relaxLocalHistory defaultSettings hinges reference mesh)
            Just _ -> do
              old <- checked (relaxSweptLocalHistory defaultSettings Motion.defaultCorrectionSettings hinges reference mesh)
              pure (sweptRelaxation old, sweptReference old)
      let learned = sweptReference guarded
          result = sweptRelaxation guarded
          atIteration n = S.toAscList (S.fromList (Local.localReferenceOrders reference ++ concatMap Local.encounterOrders (filter ((<= n) . Local.encounterIteration) (Local.localReferenceEncounters learned))))
          capture orders point = do
            model <- checked (Contact.prepareTriangleContact clearance axis orders (checkpointMesh point))
            snapshot hinges (LocalCase (curlOwners fixture) (curlBoundary fixture) axis orders model) point
      left <- case reverse (checkpoints baseline) of point : _ -> capture (Local.localReferenceOrders baselineReference) point; [] -> die "missing correction baseline"
      states <- mapM (\point -> capture (atIteration (completedIterations point)) point) (checkpoints result)
      right <- case reverse states of state : _ -> pure state; [] -> die "missing checked correction endpoint"
      let coords (V3 x y z) = [x, y, z]
          stepValue step = object ["iteration" .= correctionIteration step, "startPositions" .= map (coords . position) (samples (correctionStart step)), "finishPositions" .= map (coords . position) (samples (correctionFinish step)), "check" .= correctionValue (correctionCheck step)]
          trialValue trial =
            let known = atIteration (trialIteration trial - 1)
                failure = case trialReason trial of TrialProposalFailed (UnsafeCorrection report) -> Just (correctionValue report); _ -> Nothing
             in object
                  [ "iteration" .= trialIteration trial,
                    "lengthWeight" .= trialLengthWeight trial,
                    "scale" .= trialScale trial,
                    "beforeEnergy" .= trialBeforeEnergy trial,
                    "afterEnergy" .= trialAfterEnergy trial,
                    "includesProposedContacts" .= trialIncludesProposedContacts trial,
                    "reason" .= explain (trialReason trial),
                    "startPositions" .= map (coords . position) (samples (trialStart trial)),
                    "finishPositions" .= map (coords . position) (samples (trialFinish trial)),
                    "triangleOrders" .= known,
                    "motion" .= failure
                  ]
          summaries = M.fromList [(rejectionKind row, row) | row <- rejectionSummaries (sweptDiagnostics guarded)]
          rejectionValue kind =
            object
              [ "kind" .= show kind,
                "count" .= maybe 0 rejectionCount (M.lookup kind summaries),
                "first" .= (trialValue . firstRejection <$> M.lookup kind summaries),
                "last" .= (trialValue . lastRejection <$> M.lookup kind summaries)
              ]
          blockValue block = object ["iteration" .= blockedIteration block, "lengthWeight" .= blockedLengthWeight block]
          hingeValue hinge = object ["vertices" .= hingeVertices hinge, "role" .= show (hingeRole hinge), "restRadians" .= hingeRest hinge, "stiffness" .= hingeStiffness hinge]
          audit =
            object
              [ "rejections" .= map rejectionValue [minBound .. maxBound],
                "blockedStages" .= map blockValue (blockedStages (sweptDiagnostics guarded)),
                "direction" .= coords axis,
                "clearance" .= clearance,
                "searchDistance" .= (0.03 :: Double),
                "contactEnergy" .= (case barrier of Nothing -> "overlap-height penalty"; Just _ -> "directional-distance barrier" :: String),
                "barrierActivation" .= barrier,
                "motionDepth" .= Motion.correctionDepth Motion.defaultCorrectionSettings,
                "motionBudget" .= Motion.correctionBudget Motion.defaultCorrectionSettings,
                "hinges" .= map hingeValue hinges
              ]
          outcome = if converged result then "settled" else "not settled"
          label = (case barrier of Nothing -> if isOpening then "Checked opening" else "Checked curl"; Just _ -> if isOpening then "Distance barrier · opening" else "Distance barrier · closing") ++ " · " ++ outcome
          closingOutcome = if converged result then "This run settles with material lengths restored and every accepted correction checked." else "This run stalls before restoring material lengths. It is an unresolved relaxation result, not a finished folded shape."
          description = case barrier of
            Just activation -> (if isOpening then "The opening control keeps the same spring preferences and collision checks. The left view is its starting strip. " else "Both solvers check every accepted path. The left uses the old overlap-height penalty; the right starts resisting before an established above/below relationship can reverse, even when the triangles' projected shapes are still separate. ") ++ closingOutcome ++ " The barrier activates within " ++ show activation ++ " model units beyond numerical clearance. This is a force range, not paper thickness. Earlier layer orders remain fixed. Intermediate optimizer shapes can stretch."
            Nothing -> if isOpening then "The same sixteen-span strip starts at 22.25 degrees per bend. Controls prefer 27 degrees and passive springs prefer zero, with a 4:1 stiffness ratio; their balance opens the strip to 21.6 degrees. Every accepted straight correction clears the full-interval check. The status reports whether the endpoint meets the solver's stopping checks; intermediate optimizer shapes can stretch." else "The left solver checks only poses and finds a length-correct endpoint. The right solver also refuses crossed or unresolved paths. " ++ closingOutcome ++ " Near contact, numerical rounding can change the line search's route, so convergence can differ across platforms. The separation requirement applies to every accepted correction in either outcome."
          leftCaption = if isOpening then "Starting strip" else case barrier of Nothing -> "Endpoint checks only"; Just _ -> "Overlap-height penalty"
          rightCaption = (case barrier of Nothing -> "Checked path"; Just _ -> "Distance barrier") ++ if converged result then " · settled" else " · not settled"
      putStrLn ("Trial refusals: " ++ show [(rejectionKind row, rejectionCount row) | row <- rejectionSummaries (sweptDiagnostics guarded)] ++ "; blocked stages " ++ show (blockedStages (sweptDiagnostics guarded)))
      putStrLn (label ++ ": settled " ++ show (converged result) ++ "; " ++ show (length (sweptSteps guarded)) ++ " accepted checked corrections")
      pure (object ["title" .= (label :: String), "left" .= left, "right" .= right, "leftCaption" .= (leftCaption :: String), "rightCaption" .= (rightCaption :: String), "status" .= (if converged result then "settled" else "stalled" :: String), "description" .= (description :: String), "states" .= states, "motions" .= map stepValue (sweptSteps guarded), "trialAudit" .= audit])

correctionValue :: Motion.CorrectionCheck -> Value
correctionValue report = object ("intervals" .= Motion.correctionIntervals report : fields)
  where
    fields = case Motion.correctionOutcome report of
      Motion.CorrectionClear -> ["status" .= ("clear" :: String)]
      Motion.CorrectionCollision progress pairs -> ["status" .= ("collision" :: String), "progress" .= progress, "pairs" .= pairs]
      Motion.CorrectionDegenerate progress faces -> ["status" .= ("degenerate" :: String), "progress" .= progress, "triangles" .= faces]
      Motion.CorrectionUnresolved lo hi pairs faces -> ["status" .= ("unresolved" :: String), "interval" .= [lo, hi], "pairs" .= pairs, "triangles" .= faces]

-- Approach frames are angle-defined observations, not relaxation iterates.
-- Each snapshot carries only the orders known at that point in the sequence.
approachSnapshot :: ApproachPose -> IO Value
approachSnapshot pose = do
  let fixture = approachExample pose
      learned = approachHistory pose
      refined = exampleRefined fixture
      mesh = Paper.refinedMesh refined
      axis = V3 0 0 1
      orders = Discovery.referenceOrders learned
      (leftAngle, rightAngle) = approachAngles pose
  observation <- case reverse (Discovery.referenceObservations learned) of
    item : _ -> pure item
    [] -> die "approach pose needs a contact observation"
  surface <- checked (Paper.withLayerRequirements axis orders (exampleSurface fixture))
  which <- surfaceCase surface refined
  state <- snapshot (exampleHinges fixture) which (Checkpoint 0 mesh (maxLengthError mesh))
  let pairs values = [[unFaceId a, unFaceId b] | (a, b) <- values]
      gap candidate = object ["triangles" .= Contact.candidateTriangles candidate, "panels" .= pairs [Contact.candidatePanels candidate], "gapRange" .= Contact.candidateGapRange candidate]
  pure (object ["index" .= Discovery.observationNumber observation, "leftAngle" .= leftAngle, "rightAngle" .= rightAngle, "orders" .= pairs orders, "newOrders" .= pairs (Discovery.observationNewOrders observation), "motion" .= fmap sweepValue (Discovery.observationMotion observation), "overlaps" .= map gap (Discovery.observationCandidates observation), "state" .= state])

-- A deliberately unsafe route: one full turn returns the same endpoint,
-- while an interior pose intersects another flap. It is never observed into
-- the accepted history or sent to the relaxation solver.
sweepProbe :: ApproachPose -> IO Value
sweepProbe pose = do
  let fixture = approachExample pose
      refined = exampleRefined fixture
      mesh = Paper.refinedMesh refined
      orders = Discovery.referenceOrders (approachHistory pose)
  motion <- checked (rightFlapSweep 360 mesh)
  result <- checked (Sweep.checkSweep Sweep.defaultSweepSettings motion)
  progress <- case Sweep.sweepOutcome result of
    Sweep.SweepCollision t _ | t > 0 && t < 1 -> pure t
    _ -> die "full-turn regression needs a collision strictly between its endpoints"
  witness <- checked (Sweep.sweepMeshAt motion progress)
  endpoint <- checked (Sweep.sweepMeshAt motion 1)
  surface <- checked (Paper.withLayerRequirements (V3 0 0 1) orders (exampleSurface fixture))
  which <- surfaceCase surface refined
  state <- snapshot (exampleHinges fixture) which (Checkpoint 0 witness (maxLengthError witness))
  endState <- snapshot (exampleHinges fixture) which (Checkpoint 0 endpoint (maxLengthError endpoint))
  pure (object ["check" .= sweepValue result, "state" .= state, "endpoint" .= endState, "travelDegrees" .= (360 :: Int), "progress" .= progress])

sweepValue :: Sweep.SweepCheck -> Value
sweepValue report =
  object
    ( ("intervals" .= Sweep.sweepIntervals report) : case Sweep.sweepOutcome report of
        Sweep.SweepClear -> ["status" .= ("clear" :: String)]
        Sweep.SweepCollision t pairs -> ["status" .= ("collision" :: String), "progress" .= t, "trianglePairs" .= pairs]
        Sweep.SweepUnresolved a b pairs -> ["status" .= ("unresolved" :: String), "from" .= a, "to" .= b, "trianglePairs" .= pairs]
    )

surfaceCase :: Paper.Surface V2 -> Paper.RefinedSurface -> IO SnapshotCase
surfaceCase surface refined = do
  features <- checked (Paper.surfaceFeatures surface)
  let visible = S.fromList [creaseId edge | (edge, _) <- features]
      segments = [segment | (eid, segment) <- Paper.refinedEdges refined, S.member eid visible]
  (axis, requirements) <- maybe (die "surface bending example needs explicit panel order") pure (Paper.surfaceLayerRequirements surface)
  pure (SurfaceCase (Paper.refinedPanels refined) segments axis requirements)

data SnapshotCase = Packet FoldCase | SurfaceCase [FaceId] [(Int, Int)] V3 [(FaceId, FaceId)] | LocalCase [FaceId] [(Int, Int)] V3 [(Int, Int)] Contact.OrderedContact

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
    LocalCase owners segments axis requirements model -> do
      contacts <- checked (checkLocalTriangleContact axis requirements mesh)
      rows <- checked (Contact.orderedContacts model mesh)
      let smallest = case map contactGap rows of [] -> Nothing; gaps -> Just (minimum gaps)
      pure (map unFaceId owners, segments, ["contact" .= contacts, "packetContact" .= False, "orderDirection" .= coords axis, "panelOrders" .= ([] :: [[Int]]), "triangleOrders" .= requirements, "minimumContactResidual" .= smallest])
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
