/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "atlas.h"
#include "fontmanager.h"
#include "texture.h"
#include "texturemanager.h"

#include <framework/core/eventdispatcher.h>
#include <framework/core/resourcemanager.h>
#include <framework/otml/otml.h>

FontManager g_fonts;

FontManager::FontManager()
{
    m_defaultFont = std::make_shared<BitmapFont>("emptyfont");
}

void FontManager::terminate()
{
    m_fonts.clear();
    m_defaultFont = nullptr;
}

void FontManager::clearFonts()
{
    m_fonts.clear();
    m_defaultFont = std::make_shared<BitmapFont>("emptyfont");
}

void FontManager::importFont(std::string file)
{
    if (g_graphicsThreadId != std::this_thread::get_id()) {
        g_graphicsDispatcher.addEvent(std::bind(&FontManager::importFont, this, file));
        return;
    }
    try {
        file = g_resources.guessFilePath(file, "otfont");

        OTMLDocumentPtr doc = OTMLDocument::parse(file);
        OTMLNodePtr fontNode = doc->at("Font");

        std::string name = fontNode->valueAt("name");
        if (fontExists(name))
            return;

        // remove any font with the same name
        for(auto it = m_fonts.begin(); it != m_fonts.end(); ++it) {
            if((*it)->getName() == name) {
                m_fonts.erase(it);
                break;
            }
        }

        auto font = std::make_shared<BitmapFont>(name);
        font->load(fontNode);
        m_fonts.push_back(font);

        // set as default if needed
        if(!m_defaultFont || fontNode->valueAt<bool>("default", false))
            m_defaultFont = font;

    } catch(stdext::exception& e) {
        g_logger.error(stdext::format("Unable to load font from file '%s': %s", file, e.what()));
    }
}

bool FontManager::fontExists(const std::string& fontName)
{
    for(const BitmapFontPtr& font : m_fonts) {
        if(font->getName() == fontName)
            return true;
    }
    return false;
}

BitmapFontPtr FontManager::getFont(const std::string& fontName)
{
    // find font by name
    for(const BitmapFontPtr& font : m_fonts) {
        if(font->getName() == fontName)
            return font;
    }

    // when not found, fallback to default font
    g_logger.error(stdext::format("font '%s' not found", fontName));
    return getDefaultFont();
}

void FontManager::registerInlineImage(int code, const std::string& file, int srcX, int srcY, int srcW, int srcH, int yOffset)
{
    // Only control bytes are valid: they must not collide with real glyphs
    // (>= 32) or with whitespace control codes (\t \n \v \f \r). The latter is
    // important because Lua's setHTML/setColorText shims trim and collapse with
    // the %s class, which would silently eat \v (11) and \f (12) placeholders.
    if (code <= 0 || code >= 32 || code == '\t' || code == '\n' ||
        code == '\v' || code == '\f' || code == '\r')
        return;

    TexturePtr tex = g_textures.getTexture(file);
    if (!tex)
        return;
    // NOTE: do not call tex->update() here. This runs on the Lua thread; the GL
    // upload happens lazily on the graphics thread via Painter::setTexture when
    // the icon is first drawn.

    InlineTextImage& img = m_inlineImages[code];
    const bool wasEmpty = img.width == 0;
    img.texture = tex;
    img.srcRect = Rect(srcX, srcY, srcW, srcH);
    img.width = srcW;   // drawn 1:1 with the source region
    img.height = srcH;
    img.yOffset = yOffset;
    if (wasEmpty)
        m_inlineImageCount++;
}

void FontManager::registerStyleFont(int code, const std::string& fontName)
{
    // Same control-byte rules as inline images: never collide with real glyphs
    // (>= 32) or whitespace control codes the text layout treats specially.
    if (code <= 0 || code >= 32 || code == '\t' || code == '\n' ||
        code == '\v' || code == '\f' || code == '\r')
        return;

    const bool wasEmpty = !m_styleFonts[code] && !m_styleReset[code];
    if (fontName.empty()) {
        m_styleReset[code] = true;
        m_styleFonts[code] = nullptr;
    } else {
        m_styleReset[code] = false;
        m_styleFonts[code] = getFont(fontName); // falls back to default if missing
    }
    if (wasEmpty)
        m_styleCount++;
}

const BitmapFontPtr& FontManager::getStyleFont(int code) const
{
    static const BitmapFontPtr none;
    return (code > 0 && code < 256) ? m_styleFonts[code] : none;
}
