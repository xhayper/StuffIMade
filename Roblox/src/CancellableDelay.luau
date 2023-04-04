--!strict

return function(duration: number?, functionOrThread: ((...any) -> ...any) | thread, ...: any): () -> ()
	local thread = task.delay(duration, functionOrThread, ...)
	return function()
		task.cancel(thread)
	end
end
