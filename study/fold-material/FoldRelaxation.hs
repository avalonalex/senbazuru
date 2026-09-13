-- | Restore the material edge lengths of an already posed study mesh.
--
-- Each edge remembers its length on the original sheet. Linearise all length
-- errors about the current positions, then solve for a coordinated correction
-- (Gauss-Newton). Conjugate gradients solves that sparse linear system without
-- constructing a dense matrix; a small movement penalty removes its ambiguity.
-- A line search shortens a step until it reduces the total squared error.
-- Numerical iterations are not time steps or a folding instruction sequence.
--
-- Keeping a triangle's three sides fixes its intrinsic shape, but leaves
-- adjacent triangles free to turn about their shared edge. 'relaxPacket' also
-- penalises reversed layers of the known nearly flat packet, using contacts
-- from FoldContact. Neither version enforces paper bending or crease angles,
-- and convergence is not proof of a physically attainable folded sheet.
-- We start near the sharp-fold examples, rather than folding a flat sheet by
-- interpolating vertices. See docs/notes/restoring-material-lengths.md.
--
-- The separate 'relaxBending' experiment adds angular preferences from
-- FoldBending and tightens numerical length/contact penalties in four stages.
-- Its final convergence also checks the proposed movement, so valid lengths
-- alone cannot masquerade as an elastic equilibrium. 'relaxSurfaceContact'
-- extends that same solve to declared directional panel or local triangle orders, supplied by
-- SurfaceContact. 'relaxDiscoveredContact' learns those orders from a separate
-- reference pose and refuses new unrelated overlaps. Independent triangle
-- checks still judge each endpoint. 'relaxLocalContact' uses nearby triangle
-- discovery inside bending panels with the same fixed-reference policy.
-- 'relaxLocalHistory' extends the history from accepted separated encounters.
-- Known negative gaps remain penalty residuals during early stages; new orders
-- must have positive clearance before entering the objective. The typed policy
-- threads history through all stages without mutating it during trial evaluation.
-- 'relaxSweptLocalHistory' additionally requires a full-interval separation
-- certificate for each accepted straight numerical correction. It can stall
-- where endpoint penalties took shortcuts through paper; refusing such a path
-- does not supply a better search direction. See
-- docs/notes/checking-numerical-corrections.md for the closing comparison and
-- a settled opening control. These numerical paths can still stretch triangles.
--
-- Strict runs retain a bounded rejection audit, separately from accepted contact
-- history. A failed line search ends its penalty stage as unconverged: identical
-- inputs would only repeat the same refusal. The next weight may supply a new
-- direction, but none of these diagnostics repairs a discontinuous contact
-- objective. See docs/notes/rejected-bending-trials.md.
-- 'relaxBarrierLocalHistory' replaces that energy with distance to violating a
-- retained directional order, resisting reversal before shadows overlap. Raw
-- endpoint constraints, the full-step convergence test and the accepted-motion
-- gate remain shared. See docs/notes/directional-contact-distance.md.
module FoldRelaxation
  ( Settings (..),
    defaultSettings,
    RelaxError (..),
    Checkpoint (..),
    Relaxation (..),
    relaxLengths,
    relaxPacket,
    relaxBending,
    relaxHinges,
    relaxSurfaceContact,
    relaxDiscoveredContact,
    relaxLocalContact,
    relaxLocalHistory,
    relaxSweptLocalHistory,
    relaxBarrierLocalHistory,
    SweptRelaxation (..),
    CorrectionStep (..),
    TrialDiagnostics,
    RejectionKind (..),
    TrialReason (..),
    RejectedTrial (..),
    RejectionSummary (..),
    rejectionSummaries,
    BlockedStage (..),
    blockedStages,
    principalStrains,
    maxLengthError,
  )
where

import ContactDiscovery qualified as Discovery
import Control.Monad (foldM)
import CorrectionSweep qualified as Motion
import Data.Bifunctor (second)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import Data.Maybe (isJust, isNothing)
import FoldBending
import FoldContact
import FoldMaterial
import LocalContactDiscovery qualified as Local
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import SurfaceContact qualified as Contact

-- | Tolerance is fractional edge-length error, not a percentage or thickness.
data Settings = Settings
  { iterationLimit :: !Int,
    lengthTolerance :: !Double
  }
  deriving stock (Eq, Show)

defaultSettings :: Settings
defaultSettings = Settings 100 1e-5

data RelaxError
  = InvalidSettings
  | EmptyMesh
  | InvalidSample !Int
  | MissingVertex !Int !Int
  | DegenerateMaterialTriangle !Int
  | CollapsedEdge !Int !Int
  | UncheckablePacket !Int
  | BendingFailure !BendingError
  | SurfaceContactFailure !Contact.ContactError
  | ContactDiscoveryFailure !Discovery.DiscoveryError
  | LocalDiscoveryFailure !Local.LocalDiscoveryError
  | CorrectionFailure !Motion.CorrectionError
  | UnsafeCorrection !Motion.CorrectionCheck
  | NonFiniteObjective
  deriving stock (Eq, Show)

instance Explain RelaxError where
  explain NonFiniteObjective = "numerical correction produced a non-finite energy"
  explain (CorrectionFailure err) = explain err
  explain (UnsafeCorrection result) = case Motion.correctionOutcome result of
    Motion.CorrectionCollision progress pairs -> "numerical correction meets paper at progress " <> num progress <> "; triangle pairs " <> tshow pairs
    Motion.CorrectionDegenerate progress faces -> "numerical correction collapses triangles " <> tshow faces <> " at progress " <> num progress
    Motion.CorrectionUnresolved lo hi pairs faces -> "numerical correction could not establish separation between progress " <> num lo <> " and " <> num hi <> "; triangle pairs " <> tshow pairs <> ", possible collapsing triangles " <> tshow faces
    Motion.CorrectionClear -> "numerical correction was refused despite a clear motion report"
  explain (BendingFailure err) = explain err
  explain (SurfaceContactFailure err) = explain err
  explain (ContactDiscoveryFailure err) = explain err
  explain (LocalDiscoveryFailure err) = explain err
  explain InvalidSettings = "length relaxation needs a nonnegative iteration limit and a finite positive tolerance"
  explain EmptyMesh = "length relaxation needs at least one triangle"
  explain (InvalidSample i) = "study vertex " <> tshow i <> " has a non-finite material or spatial coordinate"
  explain (MissingVertex face i) = "study triangle " <> tshow face <> " refers to missing vertex " <> tshow i
  explain (DegenerateMaterialTriangle i) = "study triangle " <> tshow i <> " has zero area on the original sheet"
  explain (CollapsedEdge a b) = "study edge " <> tshow a <> "–" <> tshow b <> " has no usable spatial direction for a length correction"
  explain (UncheckablePacket count) = "packet contact needs triangles with nonzero horizontal area; " <> tshow count <> " cannot be checked"

data Checkpoint = Checkpoint
  { completedIterations :: !Int,
    checkpointMesh :: !MaterialMesh,
    checkpointError :: !Double
  }
  deriving stock (Eq, Show)

data Relaxation = Relaxation
  { checkpoints :: ![Checkpoint],
    converged :: !Bool
  }
  deriving stock (Eq, Show)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

-- | The two principal strains of a triangle: smallest and largest extension
-- over ALL material directions, not only its three edges. The deformation
-- sends the original (u,v) directions to du and dv. Eigenvalues of their Gram
-- matrix are squared length multipliers. A zero-area material triangle has
-- no inverse; return Nothing rather than a plausible-looking zero strain.
principalStrains :: (MaterialSample, MaterialSample, MaterialSample) -> Maybe (Double, Double)
principalStrains (a, b, c)
  | determinant == 0 || not (finite determinant) = Nothing
  | otherwise =
      let du = (1 / determinant) *^ ((cv *^ ab) ^-^ (bv *^ ac))
          dv = (1 / determinant) *^ ((bu *^ ac) ^-^ (cu *^ ab))
          aa = dot du du
          bb = dot du dv
          cc = dot dv dv
          spread = sqrt ((aa - cc) * (aa - cc) + 4 * bb * bb)
          small = sqrt (max 0 ((aa + cc - spread) / 2)) - 1
          large = sqrt (max 0 ((aa + cc + spread) / 2)) - 1
       in if finite small && finite large then Just (small, large) else Nothing
  where
    bu = materialU b - materialU a
    bv = materialV b - materialV a
    cu = materialU c - materialU a
    cv = materialV c - materialV a
    determinant = bu * cv - bv * cu
    ab = position b ^-^ position a
    ac = position c ^-^ position a

maxLengthError :: MaterialMesh -> Double
maxLengthError mesh = maximum (0 : map abs (edgeStrains mesh))

relaxLengths :: Settings -> MaterialMesh -> Either RelaxError Relaxation
relaxLengths = relaxWith NoContact Nothing

-- | Also keep the known nearly flat packet's layers in order. This is a
-- zero-thickness inequality, not a general paper collision implementation.
relaxPacket :: Settings -> FoldCase -> MaterialMesh -> Either RelaxError Relaxation
relaxPacket settings which = relaxWith (PacketContact which) Nothing settings

-- | Prefer crease rest angles and flat panels, while retaining the packet's
-- length/contact checks. Large numerical penalties approximate those constraints;
-- they are not material stiffnesses. Convergence also requires the full proposed
-- correction to be below 1e-7 sheet units at the final penalty. The iteration
-- limit applies to each of four penalty stages. A shortened line-search step alone
-- must never count as equilibrium.
relaxBending :: Settings -> Bending -> PacketRestAngles -> FoldCase -> MaterialMesh -> Either RelaxError Relaxation
relaxBending settings bending targets which mesh = do
  hinges <- either (Left . BendingFailure) Right (buildHinges bending targets which mesh)
  relaxAngular (PacketContact which) settings hinges mesh

-- | Lengths and supplied angular springs, with NO contact force. This is for
-- open-surface controls whose endpoint contact is checked independently. A
-- converged result certifies numerical/material tolerances, not layer order.
relaxHinges :: Settings -> [Hinge] -> MaterialMesh -> Either RelaxError Relaxation
relaxHinges = relaxAngular NoContact

-- | Add directional separation for declared panel or local triangle orders.
-- The same staged length/bending solve now penalises reversed gaps. Independent
-- triangle diagnostics still judge the endpoint; no motion certificate follows.
relaxSurfaceContact :: Settings -> [Hinge] -> Contact.OrderedContact -> MaterialMesh -> Either RelaxError Relaxation
relaxSurfaceContact settings hinges contact = relaxAngular (SurfaceOrder contact) settings hinges

-- | Use orders learned from a separated reference, refusing newly overlapping
-- pairs whose order that reference cannot establish. No pair list is supplied.
relaxDiscoveredContact :: Settings -> [Hinge] -> Discovery.ReferenceContact -> MaterialMesh -> Either RelaxError Relaxation
relaxDiscoveredContact settings hinges reference = relaxAngular (DiscoveredOrder reference) settings hinges

-- | The same solve with automatically discovered material-triangle partners.
-- Reference relationships remain fixed; an unknown pair reaching contact
-- rejects a trial. Separated overlaps do not by themselves need an order.
relaxLocalContact :: Settings -> [Hinge] -> Local.LocalReference -> MaterialMesh -> Either RelaxError Relaxation
relaxLocalContact settings hinges reference = relaxAngular (LocalOrder reference) settings hinges

data ContactMode = NoContact | PacketContact FoldCase | SurfaceOrder Contact.OrderedContact | DiscoveredOrder Discovery.ReferenceContact | LocalOrder Local.LocalReference

-- | Learn additional partners from accepted separated poses. The returned
-- reference includes an audit of growth. Iteration labels belong to this solve;
-- pass a newly discovered reference when starting a separately numbered run.
-- Rejected line-search trials never contribute orders or audit events.
relaxLocalHistory :: Settings -> [Hinge] -> Local.LocalReference -> MaterialMesh -> Either RelaxError (Relaxation, Local.LocalReference)
relaxLocalHistory settings hinges reference mesh = do
  (result, learned, _) <- relaxAngularWith localHistoryPolicy settings hinges reference mesh
  pure (result, learned)

-- | Audit only accepted numerical corrections. Both endpoint meshes retain
-- the original material; their intervening straight paths may stretch it.
data CorrectionStep = CorrectionStep
  { correctionIteration :: !Int,
    correctionStart :: !MaterialMesh,
    correctionFinish :: !MaterialMesh,
    correctionCheck :: !Motion.CorrectionCheck
  }
  deriving stock (Eq, Show)

data SweptRelaxation = SweptRelaxation
  { sweptRelaxation :: !Relaxation,
    sweptReference :: !Local.LocalReference,
    sweptSteps :: ![CorrectionStep],
    sweptDiagnostics :: !TrialDiagnostics
  }
  deriving stock (Eq, Show)

-- | Rejections are observations, not accepted paper or learned contact. Keep
-- counts and the first/last witness per category, so even an exhausted solve
-- retains only a bounded number of meshes. Energy failures are distinct from
-- motion failures: many trials never reach the more expensive path check.
data RejectionKind = NoDescent | ContactRefusal | InvalidTrial | PathCollision | PathCollapse | PathUnresolved
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data TrialReason
  = EnergyDidNotDecrease
  | TrialEvaluationFailed !RelaxError
  | TrialProposalFailed !RelaxError
  deriving stock (Eq, Show)

instance Explain TrialReason where
  explain EnergyDidNotDecrease = "the candidate energy did not decrease"
  explain (TrialEvaluationFailed err) = "the candidate could not be evaluated: " <> explain err
  explain (TrialProposalFailed err) = "the candidate was refused: " <> explain err

data RejectedTrial = RejectedTrial
  { trialIteration :: !Int,
    trialLengthWeight :: !Double,
    trialScale :: !Double,
    trialBeforeEnergy :: !Double,
    trialAfterEnergy :: !(Maybe Double),
    -- | The candidate energy used a tentative history extension. The starting
    -- energy always uses retained history; neither history is mutated here.
    trialIncludesProposedContacts :: !Bool,
    trialReason :: !TrialReason,
    trialStart :: !MaterialMesh,
    trialFinish :: !MaterialMesh
  }
  deriving stock (Eq, Show)

data RejectionSummary = RejectionSummary
  { rejectionKind :: !RejectionKind,
    rejectionCount :: !Int,
    firstRejection :: !RejectedTrial,
    lastRejection :: !RejectedTrial
  }
  deriving stock (Eq, Show)

-- | Every available step size was refused at this penalty weight. Moving to
-- the next weight may change the direction; repeating the same solve cannot.
data BlockedStage = BlockedStage
  { blockedIteration :: !Int,
    blockedLengthWeight :: !Double
  }
  deriving stock (Eq, Show)

data TrialDiagnostics = TrialDiagnostics !(M.Map RejectionKind RejectionSummary) ![BlockedStage]
  deriving stock (Eq, Show)

rejectionSummaries :: TrialDiagnostics -> [RejectionSummary]
rejectionSummaries (TrialDiagnostics rows _) = M.elems rows

blockedStages :: TrialDiagnostics -> [BlockedStage]
blockedStages (TrialDiagnostics _ stages) = stages

emptyDiagnostics :: TrialDiagnostics
emptyDiagnostics = TrialDiagnostics M.empty []

mergeDiagnostics :: TrialDiagnostics -> TrialDiagnostics -> TrialDiagnostics
mergeDiagnostics (TrialDiagnostics earlier aStages) (TrialDiagnostics later bStages) = TrialDiagnostics (M.unionWith combine earlier later) (aStages ++ bStages)
  where
    combine a b = a {rejectionCount = rejectionCount a + rejectionCount b, lastRejection = lastRejection b}

recordRejection :: RejectedTrial -> TrialDiagnostics -> TrialDiagnostics
recordRejection trial diagnostics = mergeDiagnostics diagnostics (TrialDiagnostics (M.singleton kind (RejectionSummary kind 1 trial trial)) [])
  where
    kind = case trialReason trial of
      EnergyDidNotDecrease -> NoDescent
      TrialEvaluationFailed err -> errorKind err
      TrialProposalFailed err -> errorKind err
    errorKind (UnsafeCorrection report) = case Motion.correctionOutcome report of
      Motion.CorrectionCollision {} -> PathCollision
      Motion.CorrectionDegenerate {} -> PathCollapse
      Motion.CorrectionUnresolved {} -> PathUnresolved
      Motion.CorrectionClear -> InvalidTrial
    errorKind LocalDiscoveryFailure {} = ContactRefusal
    errorKind ContactDiscoveryFailure {} = ContactRefusal
    errorKind _ = InvalidTrial

-- | A separate strict mode: no collision or unresolved path can contribute a
-- new pose or contact history. This may stall when endpoint-only penalties
-- previously stepped through paper; exhaustion still means unconverged.
relaxSweptLocalHistory :: Settings -> Motion.CorrectionSettings -> [Hinge] -> Local.LocalReference -> MaterialMesh -> Either RelaxError SweptRelaxation
relaxSweptLocalHistory = relaxSweptWith Nothing

-- | The same accepted-motion and endpoint rules, using a smooth directional
-- distance barrier as contact energy. The activation range is numerical.
relaxBarrierLocalHistory :: Settings -> Motion.CorrectionSettings -> Double -> [Hinge] -> Local.LocalReference -> MaterialMesh -> Either RelaxError SweptRelaxation
relaxBarrierLocalHistory settings motionSettings activation = relaxSweptWith (Just activation) settings motionSettings

relaxSweptWith :: Maybe Double -> Settings -> Motion.CorrectionSettings -> [Hinge] -> Local.LocalReference -> MaterialMesh -> Either RelaxError SweptRelaxation
relaxSweptWith barrier settings motionSettings hinges reference mesh = do
  _ <- clearMotion mesh mesh
  -- Even a zero-iteration request must start inside the barrier's domain.
  _ <- case barrier of
    Nothing -> Right []
    Just activation -> either (Left . LocalDiscoveryFailure) Right (Local.localBarrierContacts activation reference mesh)
  (result, (learned, steps), diagnostics) <- relaxAngularWith policy settings hinges (reference, []) mesh
  pure (SweptRelaxation result learned steps diagnostics)
  where
    clearMotion start finish = do
      motion <- either (Left . CorrectionFailure) Right (Motion.prepareCorrection start finish)
      report <- either (Left . CorrectionFailure) Right (Motion.checkCorrection motionSettings motion)
      case Motion.correctionOutcome report of
        Motion.CorrectionClear -> Right report
        _ -> Left (UnsafeCorrection report)
    policy = ContactPolicy measure energy propose True True
    energy state@(learned, _) current = case barrier of
      Nothing -> measure state current
      Just activation -> either (Left . LocalDiscoveryFailure) Right (Local.localBarrierContacts activation learned current)
    measure (learned, _) current = either (Left . LocalDiscoveryFailure) Right (Local.localDiscoveredContacts learned current)
    propose iteration (learned, steps) start finish = do
      report <- clearMotion start finish
      next <- either (Left . LocalDiscoveryFailure) Right (Local.extendLocalReference iteration learned finish)
      pure (next, steps ++ [CorrectionStep iteration start finish report])

-- The solver owns acceptance, while a policy owns contact measurements and
-- provisional history. Parameterising the state keeps the history result typed:
-- a fixed mode returns that mode, and growing local contact returns its reference.
data ContactPolicy state = ContactPolicy
  { measureContacts :: state -> MaterialMesh -> Either RelaxError [ContactRow],
    energyContacts :: state -> MaterialMesh -> Either RelaxError [ContactRow],
    proposeContacts :: Int -> state -> MaterialMesh -> MaterialMesh -> Either RelaxError state,
    retainTrials :: !Bool,
    stopOnFailedSearch :: !Bool
  }

localHistoryPolicy :: ContactPolicy Local.LocalReference
localHistoryPolicy = ContactPolicy measure measure propose False False
  where
    measure reference mesh = either (Left . LocalDiscoveryFailure) Right (Local.localDiscoveredContacts reference mesh)
    propose iteration reference _ mesh = either (Left . LocalDiscoveryFailure) Right (Local.extendLocalReference iteration reference mesh)

fixedPolicy :: ContactPolicy ContactMode
fixedPolicy = ContactPolicy measure measure (\_ state _ _ -> Right state) False False
  where
    measure packet mesh = case packet of
      NoContact -> Right []
      LocalOrder reference -> either (Left . LocalDiscoveryFailure) Right (Local.localDiscoveredContacts reference mesh)
      DiscoveredOrder reference -> either (Left . ContactDiscoveryFailure) Right (Discovery.discoveredContacts reference mesh)
      SurfaceOrder contact -> either (Left . SurfaceContactFailure) Right (Contact.orderedContacts contact mesh)
      PacketContact which -> case packetContacts which mesh of
        (rows, 0) -> Right rows
        (_, count) -> Left (UncheckablePacket count)

relaxAngular :: ContactMode -> Settings -> [Hinge] -> MaterialMesh -> Either RelaxError Relaxation
relaxAngular packet settings hinges mesh = do
  (result, _, _) <- relaxAngularWith fixedPolicy settings hinges packet mesh
  pure result

relaxAngularWith :: ContactPolicy state -> Settings -> [Hinge] -> state -> MaterialMesh -> Either RelaxError (Relaxation, state, TrialDiagnostics)
relaxAngularWith policy settings hinges initial mesh = do
  if iterationLimit settings == 0
    then relaxWithPolicy policy 0 initial (Just (hinges, 1e8)) settings mesh
    else do
      -- A strong length penalty from the outset makes even a rigid rotation
      -- crawl: its straight tangent step violates lengths at second order.
      -- Solve easier problems first, then tighten the SAME final constraints.
      -- Only the final stage can establish the result's convergence.
      (_, history, settled, finalState, diagnostics) <- foldM stage (mesh, [], False, initial, emptyDiagnostics) [1e2, 1e4, 1e6, 1e8]
      Right (Relaxation history settled, finalState, diagnostics)
  where
    stage (current, history, _, state, earlierDiagnostics) weight = do
      let offset = case reverse history of [] -> 0; previous : _ -> completedIterations previous
      (result, nextState, diagnostics) <- relaxWithPolicy policy offset state (Just (hinges, weight)) settings current
      let shifted = [point {completedIterations = offset + completedIterations point} | point <- checkpoints result]
          combined = history ++ (if null history then shifted else drop 1 shifted)
      case reverse (checkpoints result) of
        [] -> Left EmptyMesh
        final : _ -> Right (checkpointMesh final, combined, converged result, nextState, mergeDiagnostics earlierDiagnostics diagnostics)

relaxWith :: ContactMode -> Maybe ([Hinge], Double) -> Settings -> MaterialMesh -> Either RelaxError Relaxation
relaxWith packet bending settings mesh = do
  (result, _, _) <- relaxWithPolicy fixedPolicy 0 packet bending settings mesh
  pure result

relaxWithPolicy :: ContactPolicy state -> Int -> state -> Maybe ([Hinge], Double) -> Settings -> MaterialMesh -> Either RelaxError (Relaxation, state, TrialDiagnostics)
relaxWithPolicy policy offset initial bending settings original = do
  if iterationLimit settings < 0 || lengthTolerance settings <= 0 || not (finite (lengthTolerance settings))
    then Left InvalidSettings
    else Right ()
  if null (triangles original) then Left EmptyMesh else Right ()
  mapM_ validateSample (IM.toList vertices)
  mapM_ validateTriangle (zip [0 ..] (triangles original))
  _ <- contacts initial vertices
  edges <- mapM materialEdge (meshEdges original)
  advance edges 0 initial vertices [] emptyDiagnostics
  where
    vertices = IM.fromList (zip [0 ..] (samples original))
    validateSample (i, s) =
      let V3 x y z = position s
       in if all finite [materialU s, materialV s, x, y, z] then Right () else Left (InvalidSample i)
    vertex face i = maybe (Left (MissingVertex face i)) Right (IM.lookup i vertices)
    validateTriangle (i, (a, b, c)) = do
      triple <- (,,) <$> vertex i a <*> vertex i b <*> vertex i c
      case principalStrains triple of
        Nothing -> Left (DegenerateMaterialTriangle i)
        Just _ -> Right ()
    materialEdge (i, j) = do
      -- Indices have already been checked against their owning triangles.
      a <- vertex 0 i
      b <- vertex 0 j
      let du = materialU a - materialU b
          dv = materialV a - materialV b
      Right (i, j, sqrt (du * du + dv * dv))
    meshFrom current = original {samples = IM.elems current}
    contacts state current = measureContacts policy state (meshFrom current)
    angularRows current = case bending of
      Nothing -> Right []
      Just (hinges, _) -> either (Left . BendingFailure) Right (bendingRows hinges (meshFrom current))
    advance edges count state current history diagnostics = do
      contactRows <- contacts state current
      let mesh = meshFrom current
          residual = maxLengthError mesh
          constraintsMet = residual <= lengthTolerance settings && all ((>= negate contactTolerance) . contactGap) contactRows
          exhausted = count >= iterationLimit settings
      -- The old length-only solve stops immediately on its valid rigid control.
      -- An elastic solve must still check whether an angular force wants to move it.
      (next, nextState, stationary, accepted, trials) <-
        if exhausted || (isNothing bending && constraintsMet)
          then Right (current, state, False, False, emptyDiagnostics)
          else coordinatedStep edges contactRows count state current
      let warmingUp = maybe False ((< 1e8) . snd) bending
          done = if isNothing bending then constraintsMet else stationary && (warmingUp || constraintsMet)
          blocked = stopOnFailedSearch policy && not exhausted && not done && not accepted
          -- A failed search still consumed one iteration. Count it before
          -- advancing the penalty so its trial/history labels stay distinct.
          snapshot = Checkpoint count mesh residual
          keep = count `elem` [0, 1, 2, 5, 10, 20, 50] || done || exhausted || blocked
          history' = if keep then snapshot : history else history
          block = TrialDiagnostics M.empty [BlockedStage (offset + count + 1) (maybe 1 snd bending) | blocked]
          diagnostics' = mergeDiagnostics diagnostics (mergeDiagnostics trials block)
      if done || exhausted || blocked
        then Right (Relaxation (reverse (if blocked then Checkpoint (count + 1) mesh residual : history' else history')) done, state, diagnostics')
        else advance edges (count + 1) nextState next history' diagnostics'
    coordinatedStep edges contactRows count state current = do
      forceRows <- energyContacts policy state (meshFrom current)
      lengthRows <- mapM (edgeRow current) edges
      angles <- angularRows current
      let zero = IM.map (const (V3 0 0 0)) current
          -- Linearise all lengths together. A small penalty on movement makes
          -- the underdetermined system solvable without pinning arbitrary
          -- vertices. Conjugate gradients applies J^T J without storing it.
          damping = if isNothing bending then 1e-8 else 1e-3
          lengthWeight = maybe 1 snd bending
          contactWeight = 100 * lengthWeight
          scaleRow factor (gradient, residual) = (map (second (factor *^)) gradient, factor * residual)
          addRow values (gradient, amount) = foldl' (\acc (i, g) -> IM.adjust (^+^ (amount *^ g)) i acc) values gradient
          linearChange values gradient = sum [dot g (at i values) | (i, g) <- gradient]
          solve rows =
            let rhs = foldl' addRow zero [(gradient, -residual) | (gradient, residual) <- rows]
                action values =
                  foldl' addRow (IM.map (damping *^) values) [(gradient, linearChange values gradient) | (gradient, _) <- rows]
                square (V3 x y z) = V3 (x * x) (y * y) (z * z)
                diagonal = foldl' (\values (i, g) -> IM.adjust (^+^ square g) i values) (IM.map (const (V3 damping damping damping)) zero) (concatMap fst rows)
                divide (V3 x y z) (V3 dx dy dz) = V3 (x / dx) (y / dy) (z / dz)
                -- Contact penalties can be much stiffer along one direction.
                -- Diagonal preconditioning rescales each coordinate so
                -- those forces do not drown out the length corrections.
                precondition values = if null contactRows && isNothing bending then values else IM.intersectionWith divide values diagonal
             in conjugateGradient (if isJust bending then 3000 else if null contactRows then 300 else 600) (if isJust bending then 1e-6 else 1e-15) precondition action rhs
          -- Penalise only negative gaps: separated layers must not attract
          -- each other like glued surfaces. Include errors BELOW the stopping
          -- tolerance too, since the line-search objective includes them.
          -- Omitting their derivatives can make a non-descent step stall.
          activeRows = [(map (second (sqrt contactWeight *^)) (contactGradient row), sqrt contactWeight * contactGap row) | row <- forceRows, contactGap row < 0]
          (correction, linearSolved) = solve (map (scaleRow (sqrt lengthWeight)) lengthRows ++ activeRows ++ angles)
          objective candidateState candidate = do
            rows <- energyContacts policy candidateState (meshFrom candidate)
            bends <- angularRows candidate
            let energy =
                  lengthWeight * sum [let d = norm (position (atSample j candidate) ^-^ position (atSample i candidate)) - rest in d * d | (i, j, rest) <- edges]
                    + contactWeight * sum [let d = min 0 (contactGap row) in d * d | row <- rows]
                    + sum [r * r | (_, r) <- bends]
            if finite energy then Right energy else Left NonFiniteObjective
      before <- objective state current
      let attempt scale remaining earlier =
            let candidate = IM.mapWithKey (\i sample -> sample {position = position sample ^+^ (scale *^ at i correction)}) current
                proposed = proposeContacts policy (offset + count + 1) state (meshFrom current) (meshFrom candidate)
                reject includesProposed reason after =
                  let trial = RejectedTrial (offset + count + 1) lengthWeight scale before after includesProposed reason (meshFrom current) (meshFrom candidate)
                      recorded = if retainTrials policy then recordRejection trial earlier else earlier
                   in if remaining <= (0 :: Int) then (current, state, False, recorded) else attempt (scale / 2) (remaining - 1) recorded
             in case objective state candidate of
                  Left err -> reject False (TrialEvaluationFailed err) Nothing
                  Right after | after >= before -> reject False EnergyDidNotDecrease (Just after)
                  Right beforeProposal -> case proposed of
                    Left err -> reject False (TrialProposalFailed err) (Just beforeProposal)
                    Right candidateState -> case objective candidateState candidate of
                      Left err -> reject True (TrialEvaluationFailed err) Nothing
                      Right after | after < before -> (candidate, candidateState, True, earlier)
                      Right after -> reject True EnergyDidNotDecrease (Just after)
          (next, nextState, accepted, diagnostics) = attempt 1 30 emptyDiagnostics
      Right (next, nextState, linearSolved && maximum (0 : map norm (IM.elems correction)) <= 1e-7, accepted, diagnostics)
    edgeRow current (i, j, rest) = do
      a <- maybe (Left (MissingVertex 0 i)) Right (IM.lookup i current)
      b <- maybe (Left (MissingVertex 0 j)) Right (IM.lookup j current)
      let delta = position b ^-^ position a
          distance = norm delta
      if distance <= 0 || not (finite distance)
        then Left (CollapsedEdge i j)
        else Right ([(i, (-(1 / distance)) *^ delta), (j, (1 / distance) *^ delta)], distance - rest)
    -- All indices below originate in the validated mesh; defaults keep these
    -- lookups total without introducing partial array indexing.
    atSample = IM.findWithDefault (materialSample 0 0 (V3 0 0 0))

at :: Int -> IM.IntMap V3 -> V3
at = IM.findWithDefault (V3 0 0 0)

-- | Solve a symmetric positive definite linear system by repeatedly choosing
-- a search direction conjugate to the earlier ones. Only matrix-vector
-- products are needed, so the edge graph stays sparse. This is an inner
-- numerical solve, not a physical time integration. The Boolean records
-- whether the linear residual passed: a failed solve returning no movement
-- must not make the outer elastic problem appear to be at equilibrium.
-- A residual floor is needed near a penalised equilibrium: forces from the
-- 1e8 length penalty nearly cancel the angular forces, and their floating-point
-- subtraction cannot promise a relative error on an arbitrarily tiny remainder.
conjugateGradient :: Int -> Double -> (IM.IntMap V3 -> IM.IntMap V3) -> (IM.IntMap V3 -> IM.IntMap V3) -> IM.IntMap V3 -> (IM.IntMap V3, Bool)
conjugateGradient limit residualFloor precondition action rhs = go limit zero rhs (precondition rhs) (inner rhs (precondition rhs))
  where
    zero = IM.map (const (V3 0 0 0)) rhs
    threshold = max (residualFloor * residualFloor) (inner rhs rhs * 1e-16)
    inner a b = sum (IM.elems (IM.intersectionWith dot a b))
    add a scale b = IM.unionWith (^+^) a (IM.map (scale *^) b)
    go remaining solution residual direction productResidual
      | finite (inner residual residual) && inner residual residual <= threshold = (solution, True)
      | remaining <= 0 = (solution, False)
      | otherwise =
          let product' = action direction
              denominator = inner direction product'
           in if denominator <= 0 || not (finite denominator)
                then (solution, False)
                else
                  let alpha = productResidual / denominator
                      solution' = add solution alpha direction
                      residual' = add residual (-alpha) product'
                      scaled = precondition residual'
                      productResidual' = inner residual' scaled
                      direction' = add scaled (productResidual' / productResidual) direction
                   in go (remaining - 1) solution' residual' direction' productResidual'
