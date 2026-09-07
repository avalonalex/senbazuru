-- |
-- Module      : Senbazuru.Explain
-- Description : One method for turning any of this library's errors into words.
--
-- Every layer of senbazuru has its own error type, and they stay apart on
-- purpose: an error carries enough context to point at the offending vertex,
-- edge or face, so one flattened type would throw away exactly what makes a
-- message useful to somebody holding a four-thousand-line crease pattern. The
-- eleven types are not the duplication and are not going to be merged.
--
-- The duplication was the /convention/. Nine of the eleven had a function of
-- the same shape under a name of the same shape — @renderFoldError@,
-- @renderLoadError@, and so on down the list. The other two, 'FlatError' and
-- 'Senbazuru.Render.Steps.StepError', had none, because nothing had needed to
-- print them yet — and nothing except habit said they, or a twelfth type,
-- would get one when something did. This class is that habit written down
-- somewhere a reader can look it up, rather than a shape you have to notice.
--
-- == Why a class, when nothing dispatches on it
--
-- Nothing does, and nothing will: the caller always knows which error it is
-- holding, because it came back in a concrete @Either@. So the class buys
-- nothing at a call site — @explain err@ compiles to the same function the old
-- name did. It buys two things at the definition site. One name is now the
-- answer to "how does this project print an error". And an error nested inside
-- another is quoted by that same name wherever it appears: seven of the eleven
-- types hold a 'Senbazuru.Fold.Query.FoldError' somewhere, and their instances
-- used to import its rendering function under its own spelling in order to say
-- so.
--
-- == What this deliberately is not
--
-- __Not an 'Control.Exception.Exception' instance.__ These are values. They
-- are returned in @Either@ and matched on; nothing in the library throws and
-- nothing catches. An @Exception@ instance would suggest otherwise.
--
-- __Not a hierarchy.__ No superclass, no second method, no context parameter.
-- The types that wrap another error just call 'explain' on it, which needs
-- nothing the one method does not already give.
--
-- __Not a replacement for the nine old names.__ They are still exported, now
-- as one-line bindings, so no call site or test had to move in order to
-- introduce this. Whether they still earn their keep is a separate question
-- and a much smaller change.
module Senbazuru.Explain
  ( Explain (..),
    num,
    tshow,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showGFloat)

-- | An error that can say what it is, in words for a person at a terminal.
--
-- A message is a sentence fragment: lower case, and with no full stop at the
-- end, so that a caller can put it after a colon —
-- @"cannot render " <> path <> \": \" <> explain err@. Callers do that
-- constantly, and a message carrying its own capital letter would read wrong
-- in the middle of one.
class Explain e where
  -- | The message. Names the offending element wherever the error carries one:
  -- \"invalid FOLD file\" tells the reader nothing they did not already know.
  explain :: e -> Text

-- | A measured quantity, for a message that reports one: how far a model spans
-- in @z@, how far apart two faces put a vertex, a fold angle in degrees.
--
-- Two decisions, and the second is the one that looks wrong.
--
-- __Six digits__, because most of these numbers come out of arithmetic and
-- @show@ prints the rounding along with the answer: @0.30000000000000004@
-- where the reader wants @0.300000@, and @2.220446049250313e-16@ where they
-- want @2.220446e-16@. Six is enough to see the size of the thing, which is
-- all these messages ask of the number.
--
-- __Exponent notation below 0.1__, which is 'showGFloat''s own threshold and
-- is further up than it looks: @num 0.05@ is @5.000000e-2@, not @0.050000@.
-- That reads like a defect and is the point. Flatness is judged /relative to
-- the sheet/ — see 'Senbazuru.Geometry.V3.hasRelief' — so a 400-unit pattern
-- can be refused over a @z@ span of @1e-6@, and fixed-point would print that
-- as @0.000000@: a message telling the reader their file is a folded form
-- because a coordinate is off by nothing at all.
--
-- Not every number in a message is one of these. A /coordinate/ the caller
-- typed goes through "Senbazuru.Fold.Query"'s @coord@, which is shortest
-- round-tripping so that @0.01@ reads back as @0.01@; a thickness echoed back
-- to the user goes through 'tshow'. And not
-- "Senbazuru.Render.Svg"'s @formatNumber@, which exists to keep golden files
-- byte-identical and answers a different question: nothing compares two error
-- messages for equality.
num :: Double -> Text
num x = T.pack (showGFloat (Just 6) x "")

-- | Whatever the reader gave us, back as they would recognise it.
--
-- Most uses are the @Int@ unwrapped from a @VertexId@, @EdgeId@ or @FaceId@ —
-- the messages match on @'Senbazuru.Fold.Types.VertexId' v@ and then say
-- @tshow v@, because a reader chasing a fault wants @vertex 12@ and not
-- @vertex (VertexId 12)@.
--
-- It is also right for a 'Double' the /user/ supplied, and
-- "Senbazuru.Render.Gltf" uses it that way on purpose: @--thickness 0.001@ is
-- refused with @a thickness of 1.0e-3@, the number as @show@ writes it, so it
-- can be matched against what was typed. Reaching for 'num' there because the
-- value is a distance would print @1.000000e-3@ and break that match. The rule
-- is not the type — it is whether the number came from the reader or from us.
tshow :: (Show a) => a -> Text
tshow = T.pack . show
