# Express simple error handler function.
# Serialize errors sent as first argument of the next function to JSON response.
module.exports = () ->
  # create the according express errorHandler middleware.
  return (err, req, res, next) ->
    error = if err instanceof Error then err else new Error err 
    res.json(error.status or 400, {message: error.message})