
open import Agda.Builtin.Bool
open import Agda.Builtin.Equality
open import Agda.Builtin.Float

NaN : Float
NaN = primFloatDiv 0.0 0.0

-NaN : Float
-NaN = primFloatNegate NaN

NaN≮NaN : primFloatNumericalLess NaN NaN ≡ false
NaN≮NaN = refl

-NaN≮-NaN : primFloatNumericalLess -NaN -NaN ≡ false
-NaN≮-NaN = refl

NaN≮-NaN : primFloatNumericalLess NaN -NaN ≡ false
NaN≮-NaN = refl

-NaN<NaN : primFloatNumericalLess -NaN NaN ≡ false
-NaN<NaN = refl
