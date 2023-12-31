### =========================================================================
### SharedVector and SharedVector_Pool objects
### -------------------------------------------------------------------------
###
### A SharedVector object is an external pointer to an ordinary vector.
### A SharedVector_Pool object is *conceptually* a list of SharedVector
### objects but is actually NOT *implemented* as a list of such objects.
### This is to avoid having to generate long lists of S4 objects which the
### current S4 implementation is *very* inefficient at.
###

setClass("SharedVector",
    representation("VIRTUAL",
        xp="externalptr",
        ## Any object that is never copied on assignment would be fine here.
        ## See R/BSgenome-class.R in the BSgenome package for how this slot
        ## is used for automatic uncaching of the sequences of a BSgenome
        ## object.
        .link_to_cached_object="environment"
    ),
    prototype(
        .link_to_cached_object=new.env(hash=FALSE, parent=emptyenv())
    )
)

setClass("SharedVector_Pool",
    representation("VIRTUAL",
        xp_list="list",
        .link_to_cached_object_list="list"
    )
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Low-level utilities operating directly on an externalptr object.
###

.get_tag <- function(x)
{
    if (!is(x, "externalptr"))
        stop("'x' must be an externalptr object")
    .Call2("externalptr_get_tag", x, PACKAGE="XVector")
}

.set_tag <- function(x, tag)
{
    if (!is(x, "externalptr"))
        stop("'x' must be an externalptr object")
    .Call2("externalptr_set_tag", x, tag, PACKAGE="XVector")
}

.taglength <- function(x)
{
    if (!is(x, "externalptr"))
        stop("'x' must be an externalptr object")
    .Call2("externalptr_taglength", x, PACKAGE="XVector")
}

.tagtype <- function(x)
{
    if (!is(x, "externalptr"))
        stop("'x' must be an externalptr object")
    .Call2("externalptr_tagtype", x, PACKAGE="XVector")
}

tagIsVector <- function(x, tagtype=NA)
{
    if (!is(x, "externalptr"))
        stop("'x' must be an externalptr object")
    x_tagtype <- .tagtype(x)
    if (!is.na(tagtype))
        return(x_tagtype == tagtype)
    return(x_tagtype == "double" || extends(x_tagtype, "vector"))
}

newExternalptrWithTag <- function(tag=NULL)
{
    xp <- .Call2("externalptr_new", PACKAGE="XVector")
    .set_tag(xp, tag)
}

### Helper function (for debugging purpose).
### Print some info about an externalptr object.
### Typical use:
###   show(new("externalptr"))
setMethod("show", "externalptr",
    function(object)
        .Call2("externalptr_show", object, PACKAGE="XVector")
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### SharedVector constructor.
###

### Just dispatches on the specific constructor function (each SharedVector
### concrete subclass should define a constructor function with arguments
### 'length' and 'val').
SharedVector <- function(Class, length=0L, val=NULL)
{
    FUN <- match.fun(Class)
    FUN(length=length, val=val)
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### SharedVector getters.
###

setMethod("length", "SharedVector", function(x) .taglength(x@xp))


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### The "show" method for SharedVector objects.
###

### Return the hexadecimal representation of the address of the first
### element of the tag (i.e. the first element of the external vector).
.address0 <- function(x) .Call2("SharedVector_address0", x, PACKAGE="XVector")

.oneLineDesc <- function(x)
    paste(class(x), " of length ", length(x),
          " (data starting at address ", .address0(x), ")", sep="")

setMethod("show", "SharedVector",
    function(object)
    {
        cat(.oneLineDesc(object), "\n", sep="")
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### SharedVector_Pool low-level constructors.
###

### 'SharedVector_subclass' should be the name of a SharedVector concrete
### subclass (i.e. currently one of "SharedRaw", "SharedInteger", or
### "SharedDouble").
new_SharedVector_Pool_from_list_of_SharedVector <-
    function(SharedVector_subclass, x)
{
    if (length(x) != 0L) {
        ## We use 'class(x_elt) == SharedVector_subclass' instead of more
        ## common idiom 'is(x_elt, SharedVector_subclass)' because (1) it's
        ## faster, and (2) the SharedVector concrete subclasses should never
        ## be extended anyway (i.e. they're conceptually "final classes" to
        ## use Java terminology).
        ok <- lapply(x, function(x_elt) class(x_elt) == SharedVector_subclass)
        if (!all(unlist(ok)))
            stop("all elements in 'x' must be ", SharedVector_subclass,
                 " instances")
    }
    ans_xp_list <- lapply(x, function(x_elt) x_elt@xp)
    ans_link_to_cached_object_list <- lapply(x,
                                        function(x_elt)
                                          x_elt@.link_to_cached_object)
    ans_class <- paste(SharedVector_subclass, "_Pool", sep="")
    new2(ans_class,
         xp_list=ans_xp_list,
         .link_to_cached_object_list=ans_link_to_cached_object_list,
         check=FALSE)
}

### If 'x' is a SharedVector object, then
###
###     new_SharedVector_Pool_from_SharedVector(x)[[1L]]
###
### will be identical to 'x'.
new_SharedVector_Pool_from_SharedVector <- function(x)
{
    new_SharedVector_Pool_from_list_of_SharedVector(class(x), list(x))
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### SharedVector_Pool low-level methods.
###

setMethod("length", "SharedVector_Pool", function(x) length(x@xp_list))

setMethod("width", "SharedVector_Pool",
    function(x)
        if (length(x) == 0L) integer(0) else sapply(x@xp_list, .taglength)
)

setMethod("show", "SharedVector_Pool",
    function(object)
    {
        cat(class(object), " of length ", length(object), "\n", sep="")
        for (i in seq_len(length(object)))
            cat(i, ": ", .oneLineDesc(object[[i]]), "\n", sep="")
    }
)

setAs("SharedVector", "SharedVector_Pool",
    function(from) new_SharedVector_Pool_from_SharedVector(from)
)

### For internal use only. No argument checking!
setMethod("c", "SharedVector_Pool",
    function(x, ..., recursive=FALSE)
    {
        if (!identical(recursive, FALSE))
            stop("\"c\" method for SharedVector_Pool objects ",
                 "does not support the 'recursive' argument")
        x@xp_list <-
            do.call(c, lapply(unname(list(x, ...)),
                              function(arg) arg@xp_list))
        x@.link_to_cached_object_list <-
            do.call(c, lapply(unname(list(x, ...)),
                              function(arg) arg@.link_to_cached_object_list))
        x
    }
)

### For internal use only. No argument checking!
setMethod("[", "SharedVector_Pool",
    function(x, i, j, ..., drop=TRUE)
    {
        x@xp_list <- x@xp_list[i]
        x@.link_to_cached_object_list <- x@.link_to_cached_object_list[i]
        x
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Validity.
###

problemIfNotExternalVector <- function(what, tagmustbe="a vector")
{
    msg <- paste(what, "must be an external pointer to", tagmustbe)
    return(msg)
}

.valid.SharedVector <- function(x)
{
    if (!tagIsVector(x@xp))
        return(problemIfNotExternalVector("'x@xp'"))
    NULL
}

setValidity2("SharedVector", .valid.SharedVector)

.valid.SharedVector_Pool <- function(x)
{
    if (length(x@xp_list) != length(x@.link_to_cached_object_list))
        return("'x@xp_list' and 'x@.link_to_cached_object_list' must have the same length")
    if (!all(sapply(x@xp_list,
                    function(elt) tagIsVector(elt))))
        return(problemIfNotExternalVector("each element in 'x@xp_list'"))
    if (!all(sapply(x@.link_to_cached_object_list,
                    function(elt) is.environment(elt))))
        return("each element in 'x@.link_to_cached_object_list' must be an environment")
    NULL
}

setValidity2("SharedVector_Pool", .valid.SharedVector_Pool)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Data comparison.
###
### A wrapper to the very fast memcmp() C-function.
### Arguments MUST be the following or it will crash R:
###   x1, x2: SharedVector objects
###   start1, start2, width: single integers
### In addition: 1 <= start1 <= start1+width-1 <= length(x1)
###              1 <= start2 <= start2+width-1 <= length(x2)
### WARNING: This function is voluntarly unsafe (it doesn't check its
### arguments) because we want it to be the fastest possible!
###

SharedVector.compare <- function(x1, start1, x2, start2, width)
    .Call2("SharedVector_memcmp",
          x1, start1, x2, start2, width, PACKAGE="XVector")


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Low-level copy.
###

### 'lkup' must be NULL or an integer vector.
SharedVector.copy <- function(dest, i, imax=integer(0), src, lkup=NULL)
{
    if (!is(src, "SharedVector"))
        stop("'src' must be a SharedVector object")
    if (!is.integer(i))
        i <- as.integer(i)
    if (length(i) == 1) {
        if (length(imax) == 0)
            imax <- i
        else
            imax <- as.integer(imax)
        width <- imax - i + 1L
        .Call2("SharedVector_Ocopy_from_start",
              dest, src, i, width, lkup, FALSE, PACKAGE="XVector")
    } else {
        .Call2("SharedVector_Ocopy_from_subscript",
              dest, src, i, lkup, PACKAGE="XVector")
    }
    dest
}

### 'lkup' must be NULL or an integer vector.
SharedVector.reverseCopy <- function(dest, i, imax=integer(0), src, lkup=NULL)
{
    if (!is(src, "SharedVector"))
        stop("'src' must be a SharedVector object")
    if (length(i) != 1)
        stop("'i' must be a single integer")
    if (!is.integer(i))
        i <- as.integer(i)
    if (length(imax) == 0)
        imax <- i
    else
        imax <- as.integer(imax)
    width <- imax - i + 1L
    .Call2("SharedVector_Ocopy_from_start",
          dest, src, i, width, lkup, TRUE, PACKAGE="XVector")
    dest
}

### 'lkup' must be NULL or an integer vector.
SharedVector.mcopy <- function(dest, dest.offset, src, src.start, src.width,
                               lkup=NULL, reverse=FALSE)
{
    if (!isSingleInteger(dest.offset))
        stop("'dest.offset' must be a single integer")
    if (!is(src, "SharedVector"))
        stop("'src' must be a SharedVector object")
    if (!is.integer(src.start) || !is.integer(src.width))
        stop("'src.start' and 'src.width' must be integer vectors")
    if (!isTRUEorFALSE(reverse))
        stop("'reverse' must be TRUE or FALSE")
    .Call2("SharedVector_mcopy",
          dest, dest.offset, src, src.start, src.width, lkup, reverse,
          PACKAGE="XVector")
    dest
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Coercion.
###

### Works as long as as.integer() works on 'x'.
setMethod("as.numeric", "SharedVector",
    function(x, ...) as.numeric(as.integer(x))
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Address comparison.
###
### Be careful with the semantic of the "==" operator: the addresses are
### compared, not the data they are pointing at!
###

### Return the hexadecimal address of any R object in a string.
address <- function(x)
    .Call2("get_object_address", x, PACKAGE="XVector")

### 'x' must be a list. Fast implementation of sapply(x, address).
addresses <- function(x)
    .Call2("get_list_addresses", x, PACKAGE="XVector")

setMethod("==", signature(e1="SharedVector", e2="SharedVector"),
    function(e1, e2) address(e1@xp) == address(e2@xp)
)

setMethod("!=", signature(e1="SharedVector", e2="SharedVector"),
    function(e1, e2) address(e1@xp) != address(e2@xp)
)

