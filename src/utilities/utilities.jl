import Base.vec
export convert, promote_value, promote_for_add, promote_for_mul, promote_vexity, promote_sign, print_debug
export reverse_vexity, reverse_sign, get_vectorized_size, full, kron_prod_1, kron_prod_2

### Conversion and promotion
# TODO: The difference between conversion and promotion is messy.
function convert(::Type{CvxExpr}, x)
  if typeof(x) == CvxExpr
    return x
  else
    return Constant(x)
  end
end

# In mul_div.jl, we need to get the full matrix due to bug in kron implementation
# full however, isn't defined if x is a number, so we use this as a workaround
function full(x::Number)
  return x
end

function full(x)
  return Base.full(x)
end

# Julia cannot vectorize sparse matrices. This will handle it for now
function vec(x::SparseMatrixCSC)
  return Base.vec(full(x))
end

# computes the sparse form kronecker product of eye(sz)*x
function kron_prod_1(x, sz)
  prod = spzeros(sz*size(x, 1), sz*size(x, 2))
  for k = 1:sz
    for i = 1:size(x, 1)
      for j = 1:size(x, 2)
        prod[(k-1)*size(x, 1) + i, (k-1)*size(x, 2) + j] = x[i,j]
      end
    end
  end
  return prod
end

# computes the sparse form kronecker product of x*eye(sz)
function kron_prod_2(x, sz)
  prod = spzeros(sz*size(x, 1), sz*size(x, 2))
  for i = 1:size(x, 1)
    for j = 1:size(x, 2)
      for k = 1:sz
        prod[(i-1)*sz + k, (j-1)*sz + k] = x[i,j]
      end
    end
  end
  return prod
end

### Utility functions for arithmetic

function get_vectorized_size(sz::(Int64, Int64))
  return sz[1] * sz[2]
end

function get_vectorized_size(x::AbstractCvxExpr)
  return x.size[1] * x.size[2]
end

function promote_for_add(x::Constant, sz::(Int64, Int64))
  this = Constant(x.value * ones(sz...), x.sign)
  return this
end

function promote_for_add(x::AbstractCvxExpr, sz::(Int64, Int64))
  this = ones(sz...) * x
  return this
end

function promote_for_add(x::AbstractCvxExpr, y::AbstractCvxExpr)
  if x.size != y.size
    if maximum(x.size) == 1
      x = promote_for_add(x, y.size)
    elseif maximum(y.size) == 1
      y = promote_for_add(y, x.size)
    else
      error("size of arguments cannot be added; got $(x.size),$(y.size)")
    end
  end

  return (x, y)
end

function promote_for_mul(x::AbstractCvxExpr, sz::Int64)
  # make x into eye(sz)*x
  # make new expre for this with canon_form() X[i,i] = x
  promoted_size = sz*sz
  this = CvxExpr(:promotion, [x], x.vexity, x.sign, (sz, sz))
  
  canon_constr_array = Any[{
    # TODO we'll need to cache references to parameters in the future
    :coeffs => Any[speye(promoted_size), -sparse(vec(speye(sz)))],
    :vars => [this.uid(), x.uid()],
    :constant => spzeros(promoted_size, 1),
    :is_eq => true
  }]

  this.canon_form = ()->append!(canon_constr_array, x.canon_form())
  return this
end

function promote_for_mul(x::Constant, sz::Int64)
  this = Constant(x.value*speye(sz), x.sign)
  return this
end

function promote_for_mul(x::AbstractCvxExpr, y::AbstractCvxExpr)
  if x.size[2] != y.size[1]
    if maximum(x.size) == 1
      x = promote_for_mul(x, y.size[1])
    elseif maximum(y.size) == 1
      y = promote_for_mul(y, x.size[2])
    else
      error("size of arguments cannot be multiplied; got $(x.size),$(y.size)")
    end
  end
  return (x, y)
end

function promote_vexity(x::AbstractCvxExpr, y::AbstractCvxExpr)
  v1 = x.vexity; v2 = y.vexity; vexities = Set(v1, v2)
  if vexities == Set(:convex, :concave)
    error("expression not DCP compliant")
  elseif :convex in vexities
    return :convex
  elseif :concave in vexities
    return :concave
  elseif :linear in vexities
    return :linear
  else
    return :constant
  end
end

function promote_sign(x::AbstractCvxExpr, y::AbstractCvxExpr)
  s1 = x.sign; s2 = y.sign; signs = Set(s1, s2)
  if :any in signs || signs == Set(:pos,:neg)
    return :any
  else # then s1==s2
    return s1
  end
end

function promote_value(x::Value, sz::Int64)
  if size(x, 1) < sz
    return ones(sz, 1) * x
  end
  return x
end

function reverse_vexity(x::AbstractCvxExpr)
  vexity = x.vexity
  if vexity == :convex
    return :concave
  elseif vexity == :concave
    return :convex
  else
    return vexity
  end
end

function reverse_sign(x::AbstractCvxExpr)
  sign = x.sign
  if sign == :neg
    return :pos
  elseif sign == :pos
    return :neg
  else
    return sign
  end
end

function print_debug(debug, args...)
  if (debug)
    println(args)
  end
end

# multiple arguments
# TODO: Check if it is needed
for op = (:promote_vexity, :promote_sign, :promote_shape)
  @eval ($op)(arg1,arg2,arg3,args...) = length(args)==0 ? ($op)(($op)(arg1,arg2),arg3) : ($op)(($op)(arg1,arg2),arg3,args...)
end
