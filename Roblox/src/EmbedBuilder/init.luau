--!strict

-- Ported from https://github.com/discordjs/discord.js/blob/main/packages/builders/src/messages/embed/Embed.ts

local t = require(script.t)

-- Typing

local fieldNameType = t.string
local fieldValueType = t.string
local fieldInlineType = t.optional(t.boolean)

local embedFieldType = t.interface({
	name = fieldNameType,
	value = fieldValueType,
	inline = fieldInlineType
})
local embedFieldsArrayType = t.optional(t.array(embedFieldType))

local fieldLengthType = t.numberConstrained(0, 25)

local authorNameType = t.optional(fieldNameType)

local imageUrlType = t.optional(t.string)
local urlType = t.optional(t.match("^https?://"))

local embedAuthorType = t.interface({
	name = authorNameType,
	iconURL = imageUrlType,
	url = urlType
})

local colorType = t.optional(t.union(t.numberConstrained(0, 0xffffff), t.Color3))

local descriptionType = t.optional(t.string)
local footerTextType = t.optional(t.string)

local embedFooterType = t.interface({
	text = footerTextType,
	iconURL = imageUrlType
})

local timestampType = t.optional(t.union(t.number, t.DateTime))

local titleType = t.optional(fieldNameType)

-----------------------------------------------------------------------

export type APIEmbedFooter = {
	text: string,
	icon_url: string?,
	proxy_icon_url: string?
}

export type APIEmbedImage = {
	url: string,
	proxy_url: string?,
	height: number?,
	width: number?
}

export type APIEmbedThumbnail = {
	url: string,
	proxy_url: string?,
	height: number?,
	width: number?
}

export type APIEmbedVideo = {
	url: string?,
	proxy_url: string?,
	height: number?,
	width: number?
}

export type APIEmbedProvider = {
	name: string?,
	url: string?
}

export type APIEmbedAuthor = {
	name: string,
	url: string?,
	icon_url: string?,
	proxy_icon_url: string?
}

export type APIEmbedField = {
	name: string,
	value: string,
	inline: boolean?
}

export type APIEmbed = {
	title: string?,
	type: ("rich" | "image" | "video" | "gifv" | "article" | "link")?,
	description: string?,
	url: string?,
	timestamp: string?,
	color: number?,
	footer: APIEmbedFooter?,
	image: APIEmbedImage?,
	thumbnail: APIEmbedThumbnail?,
	video: APIEmbedVideo?,
	provider: APIEmbedProvider?,
	author: APIEmbedAuthor?,
	fields: { APIEmbedField }?
}

export type IconData = {
	iconURL: string?,
	proxyIconURL: string?,
}

export type EmbedAuthorData = IconData & {
	name: string,
	url: string?
}

export type EmbedAuthorOptions = {
	iconURL: string?,
	name: string,
	url: string?
}

export type EmbedFooterData = IconData & {
	text: string
}

export type EmbedFooterOptions = {
	iconURL: string?;
	text: string
}

export type EmbedImageData = {
	url: string,
	proxyUrl: string?,
	height: number?,
	width: number?
}

-----------------------------------------------------------------------

local function InnerDeepCopy<K, V>(orig: { [any]: any } | any, copies: { [any]: any }?): { [K]: V } | any
	local cp: { [any]: any } = copies or {}

	local copy: ({ [K]: V } | any)?

	if typeof(orig) == "table" then
		if cp[orig] then
			copy = cp[orig]
		else
			copy = {}
			cp[orig] = copy
			for k, v in next, orig, nil do
				(copy :: any)[InnerDeepCopy(k, cp)] = InnerDeepCopy(v, cp)
			end
			setmetatable(copy :: any, InnerDeepCopy(getmetatable(orig :: any), cp))
		end
	else
		copy = orig
	end

	return copy
end

local function DeepCopy<K, V>(table: { [K]: V }): { [K]: V }
	return InnerDeepCopy(table)
end

-----------------------------------------------------------------------

local EmbedBuilder = {}
EmbedBuilder.__index = EmbedBuilder

export type EmbedBuilder = typeof(setmetatable({} :: { data: APIEmbed }, EmbedBuilder))

function EmbedBuilder.new(data: APIEmbed?)
	local self = setmetatable({} :: { data: APIEmbed }, EmbedBuilder)

	self.data = DeepCopy(data or {}) :: APIEmbed

	return self
end

function EmbedBuilder.addFields(self: EmbedBuilder, ...: APIEmbedField): EmbedBuilder
	local fields = { ... }
	assert(fieldLengthType(#(self.data.fields or {}) + #fields))
	assert(embedFieldsArrayType(fields))

	if self.data.fields then
		for _, field in next, fields, nil do
			table.insert(self.data.fields, field)
		end
	else
		self.data.fields = fields
	end

	return self
end

function EmbedBuilder.setFields(self: EmbedBuilder, ...: APIEmbedField): EmbedBuilder
	local fields = { ... }
	assert(fieldLengthType(#fields))
	assert(embedFieldsArrayType(fields))

	self.data.fields = fields

	return self
end

function EmbedBuilder.setAuthor(self: EmbedBuilder, options: EmbedAuthorOptions | nil): EmbedBuilder
	if options == nil then
		self.data.author = nil
		return self
	end

	assert(embedAuthorType(options))

	self.data.author = {
		name = options.name,
		url = options.url,
		icon_url = options.iconURL
	}

	return self
end

function EmbedBuilder.setColor(self: EmbedBuilder, color: number | Color3 | nil): EmbedBuilder
	assert(colorType(color))

	if typeof(color) == "Color3" then
		local red = math.floor(color.R * 255)
		local green = math.floor(color.G * 255)
		local blue = math.floor(color.B * 255)
		
		self.data.color = bit32.rshift(red, 16) + bit32.rshift(green, 8) + blue
		
		return self
	end
	
	self.data.color = color
	
	return self
end

function EmbedBuilder.setDescription(self: EmbedBuilder, description: string | nil): EmbedBuilder
	assert(descriptionType(description))
	
	self.data.description = description
	
	return self
end

function EmbedBuilder.setFooter(self: EmbedBuilder, options: EmbedFooterOptions | nil): EmbedBuilder
	if options == nil then
		self.data.footer = nil
		return self
	end	
	
	assert(embedFooterType(options))
	
	self.data.footer = {
		text = options.text,
		icon_url = options.iconURL
	}
	
	return self
end

function EmbedBuilder.setImage(self: EmbedBuilder, url: string | nil): EmbedBuilder
	assert(imageUrlType(url))
	
	self.data.image = url and { url = url } or nil
	
	return self
end

function EmbedBuilder.setThumbnail(self: EmbedBuilder, url: string | nil): EmbedBuilder
	assert(imageUrlType(url))
	
	self.data.thumbnail = url and { url = url } or nil
	
	return self
end

function EmbedBuilder.setTimestamp(self: EmbedBuilder, timestamp: DateTime | number | nil): EmbedBuilder
	assert(timestampType(timestamp))
	
	local convertedToDatetime = timestamp and ((
		typeof(timestamp) == "number" and DateTime.fromUnixTimestamp(timestamp) or
			typeof(timestamp) == "DateTime" and timestamp
) :: DateTime) or nil
	
	self.data.timestamp = timestamp and convertedToDatetime and convertedToDatetime:ToIsoDate() or nil
	
	return self
end

function EmbedBuilder.setTitle(self: EmbedBuilder, title: string | nil): EmbedBuilder
	assert(titleType(title))
	
	self.data.title = title
	
	return self
end

function EmbedBuilder.setURL(self: EmbedBuilder, url: string | nil): EmbedBuilder
	assert(urlType(url))
	
	self.data.url = url
	
	return self
end

function EmbedBuilder.toTable(self: EmbedBuilder): APIEmbed
	return DeepCopy(self.data) :: APIEmbed
end
	
return EmbedBuilder
