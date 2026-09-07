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
-- @renderLoadError@, and so on down the list — and nothing except habit said
-- the twelfth type would get one too. This class is that habit written down
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

-- | A measured quantity, for a message that reports one.
--
-- Every use is a distance that came out of arithmetic rather than out of a
-- file — how far a model spans in @z@, a fold angle that is not a number of
-- degrees — so 'show' would print the rounding along with the answer:
-- @0.30000000000000004@ where the reader wants @0.300000@, and
-- @2.220446049250313e-16@ where they want @2.220446e-16@. Six digits is what
-- 'showGFloat' takes as its argument, and it is enough to see the size of the
-- thing, which is all these messages ask of the number.
--
-- It still gives an exponent for a small number — @1.000000e-7@ — and that is
-- wanted: a span of @0.0000001@ is easier to misread than to read.
--
-- Not "Senbazuru.Render.Svg"'s @formatNumber@, which exists to keep golden
-- files byte-identical and answers a different question: nothing compares two
-- error messages for equality.
num :: Double -> Text
num x = T.pack (showGFloat (Just 6) x "")

-- | An id or a count, for a message that names one.
--
-- Almost every use is the @Int@ unwrapped from a @VertexId@, @EdgeId@ or
-- @FaceId@ — the messages match on @'Senbazuru.Fold.Types.VertexId' v@ and
-- then say @tshow v@, because a reader chasing a fault wants @vertex 12@ and
-- not @vertex (VertexId 12)@.
tshow :: (Show a) => a -> Text
tshow = T.pack . show
