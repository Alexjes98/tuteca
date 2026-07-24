class_name ChatFilter
extends RefCounted

## Utility class for safety filtering in chat messages.
## Filters out profanity, slurs, and inappropriate expressions in both English and Spanish.

# List of bad words and expressions (lowercase)
static var BAD_WORDS: Array[String] = [
	# English
	"fuck", "fucking", "fucker", "shit", "shitty", "bitch", "asshole", "bastard",
	"crap", "dick", "pussy", "cock", "cunt", "motherfucker", "nigger", "nigga",
	"faggot", "whore", "slut", "idiot", "dumbass", "retard", "bastard", "hate",
	"kill yourself", "kys",
	# Spanish
	"mierda", "puta", "puto", "carajo", "pendejo", "pendeja", "chingar", "chingada",
	"verga", "cabron", "cabrona", "concha", "maricon", "joder", "gilipollas",
	"culero", "culera", "coño", "perra", "hijo de puta", "hdp", "mamon", "mamona"
]

## Filters text, replacing bad words and expressions with asterisks.
static func filter_text(text: String) -> String:
	if text.is_empty():
		return text
		
	var sanitized := text
	
	for word in BAD_WORDS:
		if word.is_empty():
			continue
			
		var regex := RegEx.new()
		# Pattern for word boundaries or phrase matches (case insensitive)
		var pattern := "(?i)\\b" + word + "\\b"
		var err := regex.compile(pattern)
		
		if err == OK:
			var matches := regex.search_all(sanitized)
			# Process matches backwards to maintain string indices during replacement
			for i in range(matches.size() - 1, -1, -1):
				var m := matches[i]
				var start := m.get_start()
				var length := m.get_end() - start
				var stars := "*".repeat(length)
				sanitized = sanitized.substr(0, start) + stars + sanitized.substr(start + length)
		else:
			# Fallback simple replacement if regex fails
			var pos := sanitized.findn(word)
			while pos != -1:
				var stars := "*".repeat(word.length())
				sanitized = sanitized.substr(0, pos) + stars + sanitized.substr(pos + word.length())
				pos = sanitized.findn(word, pos + stars.length())
				
	return sanitized
