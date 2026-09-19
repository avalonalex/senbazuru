-- |
-- Module      : Senbazuru.Sequence.Pretty
-- Description : A fold sequence written out as the text an author would write.
--
-- A fold sequence can be written as Haskell or as text, and both make the same
-- 'Sequence'. This module goes the other way: from the value to text. It is
-- what lets a sequence built in Haskell, loops and all, be saved as a file,
-- read by a person, and handed to the command line.
--
-- == One spelling
--
-- The text an author writes has synonyms. A fold away from the reader is
-- @mountain@ or @behind@; an angle is @90°@ or @90deg@; @precrease@ means
-- @fold and unfold@. The tree keeps only what was meant, so the printer has to
-- choose a word, and it always chooses the same one: @valley@ and @mountain@,
-- @fold and unfold@, @°@, @moving@, and @top layer@ for a count of one. A
-- caption is never touched, so a step can say \"behind\" in its caption and
-- @mountain@ in its move, and both are right.
--
-- It also leaves out exactly what the parser fills in when a source says
-- nothing: no anchor, the coloured side up, a flat start, the default layers,
-- no angle for a fold that goes all the way flat. Printing a default would
-- not be wrong, but then a sequence would not print as the text it was parsed
-- from.
--
-- Together those make the printer the definition of the language's /canonical/
-- spelling: one text for each tree. Two trees can still share a text, where a
-- bare name stands beside @to@; "Senbazuru.Sequence.Syntax"'s @canonical@ is
-- about that, and nothing here needs to call it, because the trees it
-- identifies print alike already.
--
-- == Numbers stay exact
--
-- Every number in the tree is a 'Rational', and prints as a whole number or as
-- @n\/d@ in lowest terms, never as a decimal. An author who typed @0.58@ gets
-- @29\/50@ back. That is deliberate: a decimal would have to be rounded
-- somewhere, and then the text would no longer say what the tree says.
--
-- __Two numbers look unreduced and are meant to.__ @rotate 2\/8 turn@ and
-- @turned 2\/4@ print over a fixed 8 and 4, because the tree stores the count
-- of eighths or quarters the author typed, not a fraction, and the parser
-- reads that denominator as written.
--
-- == Where parentheses go
--
-- In one place only. A fold line can be named by what it brings together:
-- @corner south-west to centre@. That form, an /alignment/, may stand alone
-- as a line, but not inside another line, because @L1 to L2 to L3@ could be
-- grouped two ways. So wherever a line is an operand of something else, an
-- alignment is wrapped: @perpendicular to (corner south-west to centre)
-- through centre@. Every other kind of line starts with its own word or
-- bracket and needs none.
--
-- == It cannot fail
--
-- 'prettySequence' is total. The tree's types allow a few values no source
-- can spell, such as a negative angle on a fold or a name with a space in it,
-- and the printer prints them as they are rather than refusing. Refusing them
-- is the checker's job; a printer that could fail would be no use for showing
-- the very sequence the checker is complaining about.
module Senbazuru.Sequence.Pretty
  ( prettySequence,
    prettyPoint,
    prettyLine,
  )
where

import Data.Char (ord)
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showHex)
import Senbazuru.Explain (tshow)
import Senbazuru.Sequence.Syntax

-- | The whole sequence as text, ending in one newline.
--
-- The layout is fixed: the version line, the header lines that are not
-- defaults, then each step after a blank line, then the closing caption after
-- a blank line. One statement to a line, two spaces of indent for each block.
-- @closing@ is kept in the header and printed last, because that is where a
-- page draws it.
prettySequence :: Sequence -> Text
prettySequence (Sequence top steps) =
  T.unlines (headerLines top <> concatMap (("" :) . stepLines . locValue) steps <> closingLines)
  where
    closingLines = case hClosing top of
      Nothing -> []
      Just caption -> ["", "closing " <> quoted caption]

headerLines :: Header -> [Text]
headerLines top =
  concat
    [ ["foldseq 1"],
      ["title " <> quoted title | Just title <- [hTitle top]],
      [sheetLine (locValue (hSheet top))],
      ["anchor " <> prettyPoint (locValue p) | Just p <- [hAnchor top]],
      ["white side up" | hSide top == WhiteUp],
      startLines (locValue (hStart top))
    ]
  where
    sheetLine = \case
      UnitSquare -> "sheet square"
      SheetFile path -> "sheet " <> quoted (T.pack path)
    startLines = \case
      StartFlat -> []
      StartFolded spec -> block "start folded" (stackingLines spec)

stepLines :: Step -> [Text]
stepLines (Step name caption moves) =
  block (T.unwords (["step"] <> nameWords <> captionWords)) (concatMap (moveLines . locValue) moves)
  where
    nameWords = [text | Just (Name text) <- [name]]
    captionWords = [quoted text | Just text <- [caption]]

-- | A block: its opening words and a brace, its lines indented, a brace.
block :: Text -> [Text] -> [Text]
block opening body = [opening <> " {"] <> map ("  " <>) body <> ["}"]

stackingLines :: StackingSpec -> [Text]
stackingLines = \case
  StackingFirst -> ["stacking first"]
  Relations relations ->
    ["layers " <> prettyPoint a <> " above " <> prettyPoint b | LayerAbove a b <- relations]

-- | A move, as the lines it takes. Most take one; a move holding a block
-- takes several.
moveLines :: Move -> [Text]
moveLines = \case
  Fold sense amount line layers seed ->
    [T.unwords (["fold", senseWord sense] <> amountWords amount <> [prettyLine line] <> layerWords layers <> seedWords seed)]
  FoldAndUnfold sense line layers seed ->
    [T.unwords (["fold and unfold", senseWord sense, prettyLine line] <> layerWords layers <> seedWords seed)]
  Unfold names -> [T.unwords ("unfold" : [text | Name text <- names])]
  TurnOver LeftRight -> ["turn over left-right"]
  TurnOver TopBottom -> ["turn over top-bottom"]
  Rotate eighths turning -> [T.unwords ["rotate", tshow eighths <> "/8", "turn", turningWord turning]]
  Anchor p -> ["anchor " <> prettyPoint p]
  Mark (Name name) p face ->
    [T.unwords (["mark", name, "=", prettyPoint p] <> ["in face containing " <> prettyPoint s | Just s <- [face]])]
  Let (Name name) (BindPoint p) -> [T.unwords ["let", name, "=", prettyPoint p]]
  Let (Name name) (BindLine line) -> [T.unwords ["let", name, "=", prettyLine line]]
  Macro call samples ->
    [T.unwords (macroWords call <> ["sample" | not (null samples)] <> map angle samples)]
  Continue (Name name) end -> [T.unwords ["continue", name, "until", angle end]]
  Together members -> block "together" (concatMap (moveLines . locValue) members)
  Pose creases ->
    block "pose" [T.unwords ["crease", segment p q, "at", angle a] | (p, q, a) <- creases]
  Repeat (Name from) to isometry ->
    [T.unwords (["repeat", from <> mconcat [".." <> text | Just (Name text) <- [to]]] <> isometryWords isometry)]
  Checkpoint path spec -> block ("checkpoint " <> quoted (T.pack path)) (stackingLines spec)
  NotModelled what -> ["not modelled " <> quoted what]
  ExpectRefused (RefusalKind kind) inner -> block ("expect refused " <> kind) (moveLines inner)
  where
    senseWord = \case
      ValleyFold -> "valley"
      MountainFold -> "mountain"
    turningWord = \case
      Clockwise -> "clockwise"
      Anticlockwise -> "anticlockwise"
    amountWords = \case
      ToFlat -> []
      Degrees a -> [angle a]
    layerWords = \case
      FlapOfFirstArgument -> []
      AllLayers -> ["all layers"]
      TopLayers 1 -> ["top layer"]
      TopLayers n -> ["top", tshow n, "layers"]
      TopFlap -> ["top flap"]
    seedWords seed = ["moving " <> prettyPoint p | Just p <- [seed]]
    isometryWords = \case
      Nothing -> []
      Just (MirroredAcross p q) -> ["mirrored across", segment p q]
      Just (TurnedQuarters quarters p) -> ["turned", tshow quarters <> "/4", "about", prettyPoint p]

macroWords :: MacroCall -> [Text]
macroWords = \case
  Collapse p keeping end ->
    ["collapse at", prettyPoint p]
      <> [T.unwords ["keeping", segment q1 q2, "flat"] | Just (q1, q2) <- [keeping]]
      <> ["until", angle end]
  RabbitEar p end -> ["rabbit-ear at", prettyPoint p, "until", angle end]
  Petal (TipAt p) end -> ["petal tip", prettyPoint p, "until", angle end]
  Petal TopFlapTip end -> ["petal top flap until", angle end]

-- | A point, as a source spells it. Exported for a message that has to quote
-- what the author wrote.
prettyPoint :: Point -> Text
prettyPoint = \case
  CornerOf corner -> "corner " <> cornerWord corner
  Centre -> "centre"
  AtSheet u v -> pair u v
  MidpointOf p q -> "midpoint of " <> segment p q
  MidpointOfEdge side -> "midpoint of edge " <> compassWord side
  FractionAlong r p q -> T.unwords ["fraction", number r, "along", segment p q]
  Meet l1 l2 -> T.unwords ["meet", operand l1, operand l2]
  EndOfCreaseOf (Name name) p -> T.unwords ["end of crease of", name, "nearest", prettyPoint p]
  PointNamed (Name name) -> name
  where
    cornerWord = \case
      SouthWest -> "south-west"
      SouthEast -> "south-east"
      NorthEast -> "north-east"
      NorthWest -> "north-west"

-- | A line standing alone, as a source spells it: after @fold@, or on the
-- right of @let@. Inside another line it may need parentheses, which
-- 'operand' adds.
prettyLine :: Line -> Text
prettyLine = \case
  EdgeOf side -> "edge " <> compassWord side
  Segment p q -> segment p q
  Onto p q -> T.unwords [prettyPoint p, "to", prettyPoint q]
  LineOnto l1 l2 nearest -> T.unwords ([operand l1, "to", operand l2] <> nearestWords nearest)
  PerpendicularThrough line p -> T.unwords ["perpendicular to", operand line, "through", prettyPoint p]
  PointToLineThrough p line q nearest ->
    T.unwords ([prettyPoint p, "to", operand line, "through", prettyPoint q] <> nearestWords nearest)
  TwoToTwo p l1 q l2 nearest ->
    T.unwords ([prettyPoint p, "to", operand l1, "and", prettyPoint q, "to", operand l2] <> nearestWords nearest)
  PointToLinePerpendicular p l1 l2 ->
    T.unwords [prettyPoint p, "to", operand l1, "perpendicular to", operand l2]
  PointToLine p line -> T.unwords [prettyPoint p, "to", operand line]
  ExistingCrease p q -> "crease " <> segment p q
  HingeOf (Name name) -> "hinge of " <> name
  CreaseOf (Name name) -> "crease of " <> name
  ModelSegment (x1, y1) (x2, y2) -> "model [" <> pair x1 y1 <> ", " <> pair x2 y2 <> "]"
  LineNamed (Name name) -> name
  where
    nearestWords nearest = ["nearest " <> prettyPoint p | Just p <- [nearest]]

-- | A line where the grammar wants a /simple/ line: as an operand of another
-- line, or of @meet@. An alignment is wrapped in parentheses there and nothing
-- else is; the module header says why. Every constructor is listed, so a kind
-- of line added later has to be put on one side or the other.
operand :: Line -> Text
operand line = case line of
  Onto {} -> wrapped
  LineOnto {} -> wrapped
  PointToLineThrough {} -> wrapped
  TwoToTwo {} -> wrapped
  PointToLinePerpendicular {} -> wrapped
  PointToLine {} -> wrapped
  EdgeOf {} -> bare
  Segment {} -> bare
  PerpendicularThrough {} -> bare
  ExistingCrease {} -> bare
  HingeOf {} -> bare
  CreaseOf {} -> bare
  ModelSegment {} -> bare
  LineNamed {} -> bare
  where
    bare = prettyLine line
    wrapped = "(" <> bare <> ")"

compassWord :: Compass -> Text
compassWord = \case
  North -> "north"
  East -> "east"
  South -> "south"
  West -> "west"

-- | @[P, Q]@
segment :: Point -> Point -> Text
segment p q = "[" <> prettyPoint p <> ", " <> prettyPoint q <> "]"

-- | @(u, v)@
pair :: Rational -> Rational -> Text
pair u v = "(" <> number u <> ", " <> number v <> ")"

-- | A whole number, or @n\/d@ in lowest terms. 'Rational' keeps itself
-- reduced with a positive denominator, so the sign is the numerator's.
number :: Rational -> Text
number r
  | denominator r == 1 = tshow (numerator r)
  | otherwise = tshow (numerator r) <> "/" <> tshow (denominator r)

-- | An angle in degrees: the number, then @°@ with nothing between.
angle :: Rational -> Text
angle a = number a <> "°"

-- | A string literal. It stays on one line whatever it holds: a quote and a
-- backslash are escaped, a newline and a tab have their usual letters, and any
-- other control character below U+0020 is written @\\u{…}@ with its code in
-- hex, so that every caption a 'Text' can hold has a spelling.
quoted :: Text -> Text
quoted text = "\"" <> T.concatMap escape text <> "\""
  where
    escape = \case
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\t' -> "\\t"
      c
        | c < ' ' -> "\\u{" <> T.pack (showHex (ord c) "") <> "}"
        | otherwise -> T.singleton c
