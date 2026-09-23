-- | Backtracking with at most one repair of each original trial.
-- A repaired candidate is checked by exactly the same acceptance predicate,
-- then either selected or discarded. A refusal never becomes the input to
-- another repair: the next trial comes from the original material direction.
-- Keeping this small control policy separate lets fast tests cover failures
-- and search exhaustion without running a body-material solve in CI.
module RestorationSearch (RepairTrial (..), searchWithRestoration) where

data RepairTrial e a = RepairTrial
  { originalTrial :: a,
    repairedTrial :: Maybe (Either e a)
  }
  deriving stock (Eq, Show)

-- | The caller supplies its finite, largest-first fraction list. Only visited
-- trials are returned; once an original or repaired candidate passes, the
-- remaining trials are not repaired. An error is retained and search continues.
searchWithRestoration :: (a -> Bool) -> (a -> Either e a) -> [a] -> ([RepairTrial e a], Maybe (Int, a))
searchWithRestoration passes repair = go 0
  where
    go _ [] = ([], Nothing)
    go index (trial : rest)
      | passes trial = ([RepairTrial trial Nothing], Just (index, trial))
      | otherwise =
          let result = repair trial
              record = RepairTrial trial (Just result)
           in case result of
                Right fixed | passes fixed -> ([record], Just (index, fixed))
                _ -> let (later, selected) = go (index + 1) rest in (record : later, selected)
