{-# LANGUAGE CPP, DeriveDataTypeable #-}

{-| Position information for syntax. Crucial for giving good error messages.
-}

module Agda.Syntax.Position
  ( -- * Positions
    Position(..)
  , positionInvariant
  , startPos
  , movePos
  , movePosByString
  , backupPos

    -- * Intervals
  , Interval(..)
  , intervalInvariant
  , takeI
  , dropI

    -- * Ranges
  , Range(..)
  , rangeInvariant
  , noRange
  , posToRange
  , rStart
  , rEnd
  , rangeToInterval
  , HasRange(..)
  , SetRange(..)
  , withRangeOf
  , fuseRange
  , fuseRanges

    -- * Tests
  , tests
  ) where

import Data.Generics (Data, Typeable)
import Data.List
import Data.Function
import Data.Set (Set)
import qualified Data.Set as Set
import Test.QuickCheck
import Control.Applicative
import Control.Monad
import Agda.Utils.TestHelpers

#include "../undefined.h"
import Agda.Utils.Impossible

{--------------------------------------------------------------------------
    Types and classes
 --------------------------------------------------------------------------}

-- | Represents a point in the input (file, position, line, col).
-- Positions and line and column numbers start from 1.
--
-- If two positions have the same 'srcFile' and 'posPos' components,
-- then the final two components should be the same as well, but since
-- this can be hard to enforce the program should not rely too much on
-- the last two components; they are mainly there to improve error
-- messages for the user.
--
-- Note the invariant which positions have to satisfy: 'positionInvariant'.
data Position = Pn { srcFile :: FilePath
                   , posPos  :: !Int
		   , posLine :: !Int
		   , posCol  :: !Int
		   }
    deriving (Typeable, Data)

positionInvariant p =
  posPos p > 0 && posLine p > 0 && posCol p > 0

importantPart p = (srcFile p, posPos p)

instance Eq Position where
  (==) = (==) `on` importantPart

instance Ord Position where
  compare = compare `on` importantPart

-- | An interval. The @rEnd@ position is not included in the interval.
--
-- Note the invariant which intervals have to satisfy: 'intervalInvariant'.
data Interval = Interval { iStart, iEnd :: !Position }
    deriving (Typeable, Data, Eq, Ord)

intervalInvariant :: Interval -> Bool
intervalInvariant i =
  all positionInvariant [iStart i, iEnd i] &&
  iStart i <= iEnd i

-- | The length of an interval, assuming that the start and end
-- positions are in the same file.
iLength :: Interval -> Int
iLength i = posPos (iEnd i) - posPos (iStart i)

-- | A range is a list of intervals. The intervals should be
-- consecutive and separated.
--
-- Note the invariant which ranges have to satisfy: 'rangeInvariant'.
newtype Range = Range [Interval]
  deriving (Typeable, Data, Eq, Ord)

rangeInvariant :: Range -> Bool
rangeInvariant (Range []) = True
rangeInvariant (Range is) =
  all intervalInvariant is &&
  and (zipWith (<) (map iEnd $ init is) (map iStart $ tail is))

-- | Things that have a range are instances of this class.
class HasRange t where
    getRange :: t -> Range

instance HasRange Interval where
    getRange i = Range [i]

instance HasRange Range where
    getRange = id

instance HasRange a => HasRange [a] where
    getRange = foldr fuseRange noRange

instance (HasRange a, HasRange b) => HasRange (a,b) where
    getRange = uncurry fuseRange

instance (HasRange a, HasRange b, HasRange c) => HasRange (a,b,c) where
    getRange (x,y,z) = getRange (x,(y,z))

-- | If it is also possible to set the range, this is the class.
--
--   Instances should satisfy @'getRange' ('setRange' r x) == r@.
class HasRange t => SetRange t where
  setRange :: Range -> t -> t

instance SetRange Range where
  setRange = const

{--------------------------------------------------------------------------
    Pretty printing
 --------------------------------------------------------------------------}

instance Show Position where
    show (Pn "" _ l c)	= show l ++ "," ++ show c
    show (Pn f  _ l c)	= f ++ ":" ++ show l ++ "," ++ show c

instance Show Interval where
    show (Interval s e) = file ++ start ++ "-" ++ end
	where
	    f	= srcFile s
	    sl	= posLine s
	    el	= posLine e
	    sc	= posCol s
	    ec	= posCol e
	    file
		| null f    = ""
		| otherwise = f ++ ":"
	    start = show sl ++ "," ++ show sc
	    end
		| sl == el  = show ec
		| otherwise = show el ++ "," ++ show ec

instance Show Range where
  show r = case rangeToInterval r of
    Nothing -> ""
    Just i  -> show i

{--------------------------------------------------------------------------
    Functions on postitions and ranges
 --------------------------------------------------------------------------}

-- | The first position in a file: position 1, line 1, column 1.
startPos :: FilePath -> Position
startPos f = Pn { srcFile = f, posPos = 1, posLine = 1, posCol = 1 }

-- | Ranges between two unknown positions
noRange :: Range
noRange = Range []

-- | Advance the position by one character.
--   A tab character (@'\t'@) will move the position to the next
--   tabstop (tab size is 8). A newline character (@'\n'@) moves
--   the position to the first character in the next line. Any
--   other character moves the position to the next column.
movePos :: Position -> Char -> Position
movePos (Pn f p l c) '\t' = Pn f (p + 1) l (div (c + 7) 8 * 8 + 1)
movePos (Pn f p l c) '\n' = Pn f (p + 1) (l + 1) 1
movePos (Pn f p l c) _	  = Pn f (p + 1) l (c + 1)

-- | Advance the position by a string.
--
--   > movePosByString = foldl' movePos
movePosByString :: Position -> String -> Position
movePosByString = foldl' movePos

-- | Backup the position by one character.
--
-- Precondition: The character must not be @'\t'@ or @'\n'@.
backupPos :: Position -> Position
backupPos (Pn f p l c) = Pn f (p - 1) l (c - 1)

-- | Extracts the interval corresponding to the given string, assuming
-- that the string starts at the beginning of the given interval.
--
-- Precondition: The string must not be too long for the interval.
takeI :: String -> Interval -> Interval
takeI s i | length s > iLength i = __IMPOSSIBLE__
          | otherwise = i { iEnd = movePosByString (iStart i) s }

-- | Removes the interval corresponding to the given string from the
-- given interval, assuming that the string starts at the beginning of
-- the interval.
--
-- Precondition: The string must not be too long for the interval.
dropI :: String -> Interval -> Interval
dropI s i | length s > iLength i = __IMPOSSIBLE__
          | otherwise = i { iStart = movePosByString (iStart i) s }

-- | Converts two positions to a range.
posToRange :: Position -> Position -> Range
posToRange p1 p2 | p1 < p2   = Range [Interval p1 p2]
                 | otherwise = Range [Interval p2 p1]

-- | Converts a range to an interval, if possible.
rangeToInterval :: Range -> Maybe Interval
rangeToInterval (Range [])   = Nothing
rangeToInterval (Range is)   = Just $ Interval { iStart = iStart (head is)
                                               , iEnd   = iEnd   (last is)
                                               }

-- | The initial position in the range, if any.
rStart :: Range -> Maybe Position
rStart r = iStart <$> rangeToInterval r

-- | The position after the final position in the range, if any.
rEnd :: Range -> Maybe Position
rEnd r = iEnd <$> rangeToInterval r

-- | Finds the least interval which covers the arguments.
fuseIntervals :: Interval -> Interval -> Interval
fuseIntervals x y = Interval { iStart = head ps, iEnd = last ps }
    where ps = sort [iStart x, iStart y, iEnd x, iEnd y]

-- | Finds a range which covers the arguments.
fuseRanges :: Range -> Range -> Range
fuseRanges (Range is) (Range js) = Range (helper is js)
  where
  helper []     js  = js
  helper is     []  = is
  helper (i:is) (j:js)
    | iEnd i < iStart j = i : helper is     (j:js)
    | iEnd j < iStart i = j : helper (i:is) js
    | iEnd i < iEnd j   = helper is (fuseIntervals i j : js)
    | otherwise         = helper (fuseIntervals i j : is) js

fuseRange :: (HasRange u, HasRange t) => u -> t -> Range
fuseRange x y = fuseRanges (getRange x) (getRange y)

-- | @x `withRangeOf` y@ sets the range of @x@ to the range of @y@.
withRangeOf :: (SetRange t, HasRange u) => t -> u -> t
x `withRangeOf` y = setRange (getRange y) x

------------------------------------------------------------------------
-- Test suite

-- | The positions corresponding to the interval, /including/ the
-- end-point. This function assumes that the two end points belong to
-- the same file. Note that the 'Arbitrary' instance for 'Position's
-- uses a single, hard-wired file name.
iPositions :: Interval -> Set Int
iPositions i = Set.fromList [posPos (iStart i) .. posPos (iEnd i)]

-- | The positions corresponding to the range, including the
-- end-points. All ranges are assumed to belong to a single file.
rPositions :: Range -> Set Int
rPositions (Range is) = Set.unions (map iPositions is)

-- | Constructs the least interval containing all the elements in the
-- set.
makeInterval :: Set Int -> Set Int
makeInterval s
  | Set.null s = Set.empty
  | otherwise  = Set.fromList [Set.findMin s .. Set.findMax s]

prop_iLength i = iLength i >= 0

prop_startPos = positionInvariant . startPos

prop_noRange = rangeInvariant noRange

prop_takeI_dropI i =
  forAll (choose (0, iLength i)) $ \n ->
    let s = replicate n ' '
        t = takeI s i
        d = dropI s i
    in
    intervalInvariant t &&
    intervalInvariant d &&
    fuseIntervals t d == i

prop_rangeToInterval (Range []) = True
prop_rangeToInterval r =
  intervalInvariant i &&
  iPositions i == makeInterval (rPositions r)
  where Just i = rangeToInterval r

prop_fuseIntervals i1 i2 =
  intervalInvariant i &&
  iPositions i ==
    makeInterval (Set.union (iPositions i1) (iPositions i2))
  where i = fuseIntervals i1 i2

prop_fuseRanges :: Range -> Range -> Bool
prop_fuseRanges r1 r2 =
  rangeInvariant r &&
  rPositions r == Set.union (rPositions r1) (rPositions r2)
  where r = fuseRanges r1 r2

instance Arbitrary Position where
  arbitrary = do
    NonZero (NonNegative pos) <- arbitrary
    let line = pred pos `div` 10 + 1
        col  = pred pos `mod` 10 + 1
    return (Pn {srcFile = "file name", posPos = pos,
                posLine = line, posCol = col })

instance Arbitrary Interval where
  arbitrary = do
    (p1, p2) <- liftM2 (,) arbitrary arbitrary
    let [p1', p2'] = sort [p1, p2]
    return (Interval p1' p2')

instance Arbitrary Range where
  arbitrary = Range . fixUp . sort <$> arbitrary
    where
    fixUp (i1 : i2 : is)
      | iEnd i1 >= iStart i2 = fixUp (fuseIntervals i1 i2 : is)
      | otherwise            = i1 : fixUp (i2 : is)
    fixUp is = is

-- | Test suite.
tests = runTests "Agda.Syntax.Position"
  [ quickCheck' positionInvariant
  , quickCheck' intervalInvariant
  , quickCheck' rangeInvariant
  , quickCheck' prop_iLength
  , quickCheck' prop_startPos
  , quickCheck' prop_noRange
  , quickCheck' prop_takeI_dropI
  , quickCheck' prop_rangeToInterval
  , quickCheck' prop_fuseIntervals
  , quickCheck' prop_fuseRanges
  ]
