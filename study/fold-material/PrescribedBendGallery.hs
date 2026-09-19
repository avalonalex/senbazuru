-- | Inspect prescribed energy probes without running a material solve. All
-- plots use one side camera and scale; coordinates and spring/edge records
-- retain the evidence behind the table. Old grips are measured, not imposed.
-- A length-invalid cylinder is still useful evidence and never an equilibrium.
module PrescribedBendGallery (writePrescribedBends) where

import ClosedCrease
import Control.Monad (forM)
import CoupledCrease
import CreasePairContact
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (componentCount)
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import UnequalCrease

probes :: [(String, Text, BendProbe)]
probes = [("flat", "Flat touching panels", FlatPanels), ("corners", "Existing fixed corners", FixedCorners), ("cylinder", "Sampled cylinder", SampledCylinder), ("fixed-edges", "Cylinder with full-length edges", FixedEdges)]

writePrescribedBends :: FilePath -> IO ()
writePrescribedBends destination = do
  let output = destination </> "prescribed-bend"
  createDirectoryIfMissing True output
  preference <- checked bandPreference
  runs <- forM [(p, size) | p <- probes, size <- probeMeshes] $ \((key, title, probe), (n, w)) -> do
    fixture <- checked (prescribedFixture n w probe)
    measured <- checked (measureProbe fixture)
    gaps <- checked (auditPairContact (closedOwners fixture) (closedMesh fixture))
    original <- checked (unequalCreaseWithWidth n w UpperBand)
    sheet <- checked (closedSurface fixture)
    let mesh = closedMesh fixture
        stem = key ++ "-" ++ show n ++ "x" ++ show w
        rows = IM.fromList (zip [0 ..] (samples mesh))
        gripChange = maximum (0 : [norm (position p ^-^ old) | (i, old) <- IM.toList (coupledPins original), Just p <- [IM.lookup i rows]])
        tipError = maximum (0 : [norm (position p ^-^ cylinderPoint (abs (materialU p)) (materialV p)) | p <- samples mesh])
        energy weight = weight * probeLengthSquares measured / 2
        angular = probeLowerEnergy measured + probeUpperEnergy measured + probeControlEnergy measured + probeCreaseEnergy measured
        report =
          object
            [ "id" .= stem,
              "probe" .= key,
              "title" .= title,
              "length" .= n,
              "width" .= w,
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "sharedCreaseVertices" .= closedRoot fixture,
              "maxOriginalGripDisplacement" .= gripChange,
              "maxVertexDistanceToCylinder" .= tipError,
              "lowerPassive" .= probeLowerEnergy measured,
              "upperPassive" .= probeUpperEnergy measured,
              "imposed" .= probeControlEnergy measured,
              "crease" .= probeCreaseEnergy measured,
              "lengthSquares" .= probeLengthSquares measured,
              "maxRelativeEdgeError" .= probeRelativeError measured,
              "meetsLengthCap" .= (probeRelativeError measured <= 1e-5),
              "maxCreaseError" .= probeCreaseError measured,
              "minimumExactGap" .= show (pairMinimum gaps),
              "maximumExactGap" .= show (pairMaximum gaps),
              "knownOrderPasses" .= (pairMinimum gaps >= 0),
              "lengthPenalties" .= [object ["weight" .= weight, "halfSquaredEnergy" .= energy weight, "lineSearchObjective" .= (2 * (energy weight + angular))] | weight <- [1e2, 1e4, 1e6, 1e8, 1e9, 1e10]],
              "profile" .= (stem ++ ".svg"),
              "fold" .= (stem ++ ".fold"),
              "detail" .= (stem ++ ".json")
            ]
        detail =
          object
            [ "summary" .= report,
              "vertices" .= [object ["material" .= [materialU p, materialV p], "position" .= [x, y, z]] | p <- samples mesh, let V3 x y z = position p],
              "triangles" .= [[a, b, c] | (a, b, c) <- triangles mesh],
              "edges" .= [object ["vertices" .= [a, b], "rest" .= edgeRest e, "actual" .= edgeActual e] | e <- probeEdges measured, let (a, b) = edgeIds e],
              "hinges" .= map hingeJson (probeHinges measured)
            ]
    BL.writeFile (output </> stem ++ ".json") (encode detail)
    BL.writeFile (output </> stem ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru prescribed bend study") Nothing (Just title) Nothing [] (materialFrame sheet) []))
    TIO.writeFile (output </> stem ++ ".svg") (profileSvg title fixture)
    pure report
  let document =
        object
          [ "curvature" .= curvature,
            "panelStiffness" .= (0.2 :: Double),
            "bandDesiredTurn" .= bandDesiredTurn preference,
            "bandBounds" .= bandBounds preference,
            "bandBendingWeight" .= bandBendingWeight preference,
            "bandFlatEnergy" .= bandReferenceEnergy preference,
            "lengthCap" .= (1e-5 :: Double),
            "equilibriumSolved" .= False,
            "contactCorrected" .= False,
            "continuousMotionChecked" .= False,
            "originalHoldsApplied" .= False,
            "runs" .= runs
          ]
  BL.writeFile (output </> "checks.json") (encode document)
  template <- TIO.readFile "study/fold-material/prescribed-bend.html"
  TIO.writeFile (destination </> "prescribed-bend.html") (T.replace "/*PRESCRIBED_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote prescribed-bend.html and 32 measured profiles with FOLD and raw diagnostics to " ++ destination)

hingeJson :: HingeMeasure -> Value
hingeJson h =
  object
    [ "vertices" .= [a, b, c, d],
      "role" .= show (hingeRole hinge),
      "upper" .= measuredUpper h,
      "rest" .= hingeRest hinge,
      "stiffness" .= hingeStiffness hinge,
      "angle" .= measuredAngle h,
      "energy" .= measuredEnergy h
    ]
  where
    hinge = measuredHinge h
    (a, b, c, d) = hingeVertices hinge

-- Equal x/z scales, with the exact cylinder shown as a dense reference line.
-- The two paper layers coincide, so dashed ochre lies on solid teal. Every
-- mesh shares this extent; no automatic fitting hides refinement changes.
profileSvg :: Text -> ClosedCrease -> Text
profileSvg title fixture =
  renderSvg defaultPage {pageWidth = 720, pageHeight = 300, pageMargin = 20, pageBackground = Nothing, pageTitle = Just title} $
    diagramWithExtent
      (Box (V2 (-0.03) (-0.035)) (V2 0.55 0.19))
      [ Polyline (solid (Colour "#c4bfb4") 1) [V2 0 0, V2 0.5 0],
        Polyline (solid (Colour "#bbb6ab") 3) [side (cylinderPoint (fromIntegral i / 400) 0) | i <- [0 :: Int .. 200]],
        Polyline (solid (Colour "#397f88") 2.5) profile,
        Polyline (Stroke (Colour "#b35836") 1.5 (Dash [5, 5])) profile,
        Label (Colour "#70685b") 12 (V2 0 (-0.02)) "crease",
        Label (Colour "#70685b") 12 (V2 0.45 (-0.02)) "x = 0.5"
      ]
  where
    side (V3 x _ z) = V2 x z
    profile = [side (position p) | p <- samples (closedMesh fixture), materialU p >= 0, materialV p == -0.5]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
