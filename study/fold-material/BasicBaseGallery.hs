-- | Reproducible endpoint gallery for the six additional traditional bases.
-- Kept separate from packet relaxation so these small regression fixtures can
-- be regenerated quickly. All drawings use the production SVG backend; only
-- the HTML layout lives here. FOLD downloads retain shared material vertices
-- and explicit layer orders. The optional spread-layer drawings move paper
-- on the page for inspection, not in the exported geometry.
module BasicBaseGallery (writeBasicBases) where

import BasicBases
import Control.Monad (forM, forM_, unless)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldMaterial
import PanelContact
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Explain (Explain, explain)
import Senbazuru.Fold.Query (Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Origami.Folding (Folded (..), foldFrameWith)
import Senbazuru.Origami.Stacking (defaultBudget, solveStacking)
import Senbazuru.Render.Camera (View (..), bottomUp, topDown)
import Senbazuru.Render.CreasePattern (creasePatternAuto)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import StudyCase (PoseSpec (..), StudyPose (..), buildPose)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeBasicBases :: FilePath -> IO ()
writeBasicBases destination = do
  createDirectoryIfMissing True destination
  entries <- mapM (writeBase destination) basicBases
  template <- TIO.readFile "study/fold-material/basic-bases.html"
  TIO.writeFile (destination </> "basic-bases.html") (T.replace "<!--BASES-->" (T.concat (map fst entries)) template)
  BL.writeFile (destination </> "basic-base-measurements.json") (encode (map snd entries))
  putStrLn ("Wrote six base endpoints, SVG views and basic-bases.html to " ++ destination)

writeBase :: FilePath -> Base -> IO (T.Text, Value)
writeBase destination base = do
  source <- checked (baseFrame base)
  let file = baseFile base source
  result <- checked (foldFrameWith source)
  orders <- checked (solveStacking (foldedFrame result))
  let final = (foldedFrame result) {faceOrders = orders}
  pose <- checked (buildPose 1 source (PoseSpec "closed endpoint" (edgesFoldAngle source)))
  faces <- checked (frameFaces final)
  alongZ <- forM orders $ \(FaceOrder a b stacking) -> do
    face <- maybe (die "base layer order names a missing face") pure (lookup b [(faceId f, f) | f <- faces])
    let V3 _ _ z = polygonNormal (faceCorners face)
        name = T.pack . show . unFaceId
    unless (abs z > 1e-12 && stacking /= Unordered) (die "base layer order needs an oriented flat face")
    pure (if (stacking == Above) == (z > 0) then (name b, name a) else (name a, name b))
  contact <- checked (checkPanelContact (V3 0 0 1) alongZ [Panel (T.pack (show (unFaceId (faceId f)))) (faceCorners f) | f <- faces])
  let mesh = poseMesh pose
      strain = maximum (0 : map abs (edgeStrains mesh))
      area = areaRatio mesh
  unless (contactPassed contact && componentCount mesh == 1 && strain < 1e-12 && abs (area - 1) < 1e-12) $
    die (baseId base ++ ": endpoint failed material or contact checks")
  BL.writeFile (path "cp.fold") (encode file)
  BL.writeFile (path "folded.fold") (encode file {keyFrame = final})
  draw "cp" defaultTheme topDown source
  forM_ [("front", topDown), ("reverse", bottomUp)] $ \(view, basis) -> do
    draw view defaultTheme basis final
    draw (view ++ "-layers") defaultTheme {themeLayerOffset = 4} basis final
  pure
    ( card base (length faces) (checkedPanelPairs contact),
      object
        [ "base" .= baseId base,
          "vertices" .= length (verticesCoords final),
          "panels" .= length faces,
          "maxEdgeStrain" .= strain,
          "areaRatio" .= area,
          "components" .= componentCount mesh,
          "checkedPanelPairs" .= checkedPanelPairs contact,
          "crossingPanels" .= crossingPanels contact,
          "unorderedContacts" .= unorderedContacts contact,
          "reversedOrders" .= reversedOrders contact,
          "uncheckedOrders" .= uncheckedOrders contact,
          "faceOrders" .= orders
        ]
    )
  where
    path suffix = destination </> baseId base ++ "-base-" ++ suffix
    draw name theme basis sheet = do
      diagram <- checked (creasePatternAuto theme defaultBudget (View (Just basis) 0) sheet)
      TIO.writeFile (path (name ++ ".svg")) (renderSvg defaultPage {pageWidth = 400, pageHeight = 400, pageMargin = 36} diagram)

card :: Base -> Int -> Int -> T.Text
card base panels pairs =
  let key = T.pack (baseId base)
      title = escapeXml (baseTitle base)
      prefix = key <> "-base-"
      side = if baseId base `elem` ["helmet", "diamond"] then "reverse" else "front"
      caption = "Closed endpoint · " <> side <> " view"
      link suffix label = "<a href=\"" <> prefix <> suffix <> "\" download>" <> label <> "</a>"
   in "<article id=\""
        <> key
        <> "\"><header><h2>"
        <> title
        <> "</h2><span>"
        <> T.pack (show panels)
        <> " panels · "
        <> T.pack (show pairs)
        <> " contact pairs</span></header>"
        <> "<p>"
        <> escapeXml (baseDescription base)
        <> "</p><div class=\"figures\">"
        <> "<figure><img src=\""
        <> prefix
        <> "cp.svg\" alt=\""
        <> title
        <> " crease pattern\"><figcaption>Crease pattern</figcaption></figure>"
        <> "<figure><img class=\"endpoint\" data-base=\""
        <> key
        <> "\" data-flap-side=\""
        <> side
        <> "\" src=\""
        <> prefix
        <> side
        <> ".svg\" alt=\""
        <> title
        <> " · "
        <> caption
        <> "\"><figcaption class=\"view-label\">"
        <> caption
        <> "</figcaption></figure></div>"
        <> "<footer>"
        <> link "cp.fold" "Crease FOLD"
        <> link "folded.fold" "Folded FOLD"
        <> link (side <> ".svg") "SVG"
        <> "<span>Material + contact checks passed</span></footer></article>"

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
