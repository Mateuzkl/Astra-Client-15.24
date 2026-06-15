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

#include "uiitem.h"
#include "spritemanager.h"
#include "game.h"
#include <framework/otml/otml.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/fontmanager.h>
#include <framework/graphics/texturemanager.h>

UIItem::UIItem()
{
    m_draggable = true;
    m_color = Color(231, 231, 231);
    m_itemColor = Color::white;
    m_lastDecayUpdate = 0;
    m_decayColor = Color(127, 255, 212);
    m_decayPausedColor = Color(222, 109, 109);
}

void UIItem::drawSelf(Fw::DrawPane drawPane)
{
    if(drawPane != Fw::ForegroundPane)
        return;
    // draw style components in order
    if(m_backgroundColor.aF() > Fw::MIN_ALPHA) {
        Rect backgroundDestRect = m_rect;
        backgroundDestRect.expand(-m_borderWidth.top, -m_borderWidth.right, -m_borderWidth.bottom, -m_borderWidth.left);
        drawBackground(m_rect);
    }

    drawImage(m_rect);

    if(m_itemVisible && m_item) {
        Rect drawRect = getPaddingRect();

        int exactSize = std::max<int>(g_sprites.spriteSize(), m_item->getExactSize());
        if(exactSize == 0)
            return;

        m_item->setColor(m_itemColor);
        m_item->draw(drawRect);

        if(m_font && m_showCount && (m_showCountAlways || (m_item->isStackable() || m_item->isChargeable() || m_item->isQuiver()) && m_item->getCountOrSubType() > 1)) {
            g_drawQueue->addText(m_font, m_countText, Rect(drawRect.topLeft(), drawRect.bottomRight() - Point(3, 0)), Fw::AlignBottomRight, m_color);
        }

        if (m_showId) {
            g_drawQueue->addText(m_font, std::to_string(m_item->getServerId()), drawRect, Fw::AlignBottomRight, m_color);
        }

        if (g_game.getFeature(Otc::GameDisplayItemDuration)) {
            if (m_item->getDurationTime() > 0) {
                auto isPaused = m_item->isDurationPaused();
                if (m_lastDecayUpdate + 1000 < stdext::millis()) {
                    uint64 duration = m_item->getDurationTime() - (isPaused ? m_item->getDurationTimePaused() : stdext::unixtimeMs());
                    m_decayText = stdext::secondsToDuration(duration / 1000);
                    m_lastDecayUpdate = stdext::millis();
                }
                g_drawQueue->addText(m_font, m_decayText, drawRect, Fw::AlignBottomRight, isPaused ? m_decayPausedColor : m_decayColor);
            }
        }

        // Tier badge: the small orange classification badge with the tier number,
        // drawn at the top-right of the slot. Artwork:
        // data/images/game/items/tier-<n>.png with n = 1..10 (the "big" variant is
        // for detail views and is far too large for an inventory slot).
        if (m_item->getTier() > 0) {
            int tier = std::min<int>(m_item->getTier(), 10);
            const TexturePtr& tierTexture = g_textures.getTexture("/images/game/items/tier-" + std::to_string(tier));
            if (tierTexture) {
                Size tierSize = tierTexture->getSize();
                Rect tierRect(drawRect.topRight() - Point(tierSize.width() - 1, 0), tierSize);
                g_drawQueue->addTexturedRect(tierRect, tierTexture, Rect(0, 0, tierSize));
            }
        }

        // Upgrade badge (custom server upgrade system): green for weapons, blue for
        // set pieces (helmet/armor/legs/boots). Drawn at the top-left so it never
        // collides with the tier badge (top-right) or the count/duration (bottom-right).
        // A single blank badge image per colour is used and the upgrade level number
        // is drawn on top as text (so any level is supported, e.g. +12). Artwork
        // (to be supplied): /images/game/items/upgrade-weapon.png (green) and
        // /images/game/items/upgrade-set.png (blue).
        if (m_item->getUpgradeLevel() > 0) {
            ThingType* tt = m_item->rawGetThingType();
            std::string variant;
            if (tt) {
                const int slot = tt->getClothSlot();
                const bool isSetPiece = (slot == Otc::InventorySlotHead || slot == Otc::InventorySlotArmor ||
                                         slot == Otc::InventorySlotLegs || slot == Otc::InventorySlotFeet);
                // Set pieces (helmet/armor/legs/boots) -> blue; any other upgraded item
                // -> weapon (green). getWeaponType() is unreliable for some weapons
                // (wands/rods report 0), and the server's upgrade system only marks
                // weapons + set pieces, so "not a set piece" => weapon is robust.
                variant = isSetPiece ? "set" : "weapon";
            }
            if (!variant.empty()) {
                const TexturePtr& upgradeTexture = g_textures.getTexture("/images/game/items/upgrade-" + variant);
                if (upgradeTexture) {
                    // Scale the small colour chip up (native art is only 9x8) so a 1-2
                    // digit upgrade level (+1..+12) stays legible in the top-left corner.
                    const Size texSize = upgradeTexture->getSize();
                    const int bw = std::max<int>(13, drawRect.width() * 42 / 100);
                    const int bh = std::max<int>(11, drawRect.height() * 36 / 100);
                    Rect upgradeRect(drawRect.topLeft(), Size(bw, bh));
                    g_drawQueue->addTexturedRect(upgradeRect, upgradeTexture, Rect(0, 0, texSize));
                    if (m_font)
                        g_drawQueue->addText(m_font, std::to_string(m_item->getUpgradeLevel()), upgradeRect, Fw::AlignCenter, Color::white, true);
                }
            }
        }
    }

    drawBorder(m_rect);
    drawIcon(m_rect);
    drawText(m_rect);
}

void UIItem::setItemId(int id)
{
    if (!m_item && id != 0)
        m_item = Item::create(id);
    else {
        // remove item
        if (id == 0)
            m_item = nullptr;
        else
            m_item->setId(id);
    }

    if (m_item)
        m_item->setShader(m_shader);

    m_lastDecayUpdate = 0;

    callLuaField("onItemChange");
}

void UIItem::setItemCount(int count)
{
    if (m_item) {
        m_item->setCount(count);
        callLuaField("onItemChange");
        cacheCountText();
    }
}

void UIItem::setItemSubType(int subType)
{
    if (m_item) {
        m_item->setSubType(subType);
        callLuaField("onItemChange");
    }
}

void UIItem::setItem(const ItemPtr& item)
{
    m_item = item;
    if (m_item) {
        m_item->setShader(m_shader);

        m_lastDecayUpdate = 0;

        cacheCountText();
        callLuaField("onItemChange");
    }
}

void UIItem::setItemShader(const std::string& str)
{
    m_shader = str;

    if (m_item) {
        m_item->setShader(m_shader);
        callLuaField("onItemChange");
    }
}

void UIItem::onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);

    for(const OTMLNodePtr& node : styleNode->children()) {
        if(node->tag() == "item-id")
            setItemId(node->value<int>());
        else if(node->tag() == "item-count")
            setItemCount(node->value<int>());
        else if(node->tag() == "item-visible")
            setItemVisible(node->value<bool>());
        else if(node->tag() == "virtual")
            setVirtual(node->value<bool>());
        else if(node->tag() == "show-id")
            m_showId = node->value<bool>();
        else if(node->tag() == "shader")
            setItemShader(node->value());
        else if(node->tag() == "item-color")
            setItemColor(node->value<Color>());
        else if(node->tag() == "item-always-show-count")
            setShowCountAlways(node->value<bool>());
    }
}

void UIItem::cacheCountText()
{
    int count = m_item->getCountOrSubType();
    if (!g_game.getFeature(Otc::GameCountU16) || count < 1000) {
        m_countText = std::to_string(count);
        return;
    }

    m_countText = stdext::format("%.0fk", count / 1000.0);
}
