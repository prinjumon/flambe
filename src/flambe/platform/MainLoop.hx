//
// Flambe - Rapid game development
// https://github.com/aduros/flambe/blob/master/LICENSE.txt

package flambe.platform;

import flambe.Component;
import flambe.display.Graphics;
import flambe.display.Sprite;
import flambe.Entity;
import flambe.scene.Director;
import flambe.System;
import flambe.Visitor;

using Lambda;

/**
 * Updates all components and renders.
 */
class MainLoop
{
    public function new ()
    {
        _updateVisitor = new UpdateVisitor();
        _drawVisitor = new DrawVisitor();
        _tickables = [];
    }

    public function update (dt :Float)
    {
        if (dt <= 0) {
            // This can happen on platforms that don't have monotonic timestamps and are prone to
            // system clock adjustment
            Log.warn("Zero or negative time elapsed since the last frame!", ["dt", dt]);
            return;
        }
        if (dt > 1) {
            // Clamp deltaTime to a reasonable limit. Games tend not to cope well with huge
            // deltaTimes. Platforms should skip the next frame after unpausing to prevent sending
            // huge deltaTimes, but not all environments support detecting an unpause
            dt = 1;
        }

        // First update any tickables, folding away nulls
        var ii = 0;
        while (ii < _tickables.length) {
            var t = _tickables[ii];
            if (t == null || t.update(dt)) {
                _tickables.splice(ii, 1);
            } else {
                ++ii;
            }
        }

        // Then update the entity hierarchy
        _updateVisitor.init(dt);
        System.root.visit(_updateVisitor, true, true);
    }

    public function render (renderer :Renderer)
    {
        var graphics = renderer.willRender();
        if (graphics != null) {
            _drawVisitor.init(graphics);
            System.root.visit(_drawVisitor, false, true);
            renderer.didRender();
        }
    }

    public function addTickable (t :Tickable)
    {
        _tickables.push(t);
    }

    public function removeTickable (t :Tickable)
    {
        var idx = _tickables.indexOf(t);
        if (idx >= 0) {
            // Actual removals only happen in update()
            _tickables[idx] = null;
        }
    }

    private var _updateVisitor :UpdateVisitor;
    private var _drawVisitor :DrawVisitor;

    private var _tickables :Array<Tickable>;
}

private class UpdateVisitor
    implements Visitor
{
    public function new ()
    {
        _step = new Timestep();
    }

    inline public function init (dt :Float)
    {
        _step.dt = dt;
    }

    public function enterEntity (entity :Entity) :Bool
    {
        var speed = entity.get(SpeedAdjuster);
        if (speed != null) {
            var scale = speed.scale._;
            if (scale <= 0) {
                // This entity is paused, avoid descending into children. But do update the speed
                // adjuster (so it can still be animated)
                speed.onUpdate(_step.dt);
                return false;
            }
            if (scale != 1) {
                // Push this entity onto the timestep stack
                var prev = _step;
                var prevDt = prev.dt;
                _step = new Timestep();
                _step.dt = prevDt * scale;
                _step.entity = entity;
                _step.next = prev;

                // Let the adjuster know the previous delta, so it doesn't affect itself
                speed._internal_realDt = prevDt;
            }
        }

        return true;
    }

    public function leaveEntity (entity :Entity)
    {
        // If this entity caused a speed adjustment, pop it off the timestep stack
        if (entity == _step.entity) {
            _step = _step.next;
        }
    }

    public function acceptComponent (component :Component)
    {
        component.onUpdate(_step.dt);
    }

    private var _step :Timestep;
}

private class Timestep
{
    public var entity :Entity = null;
    public var dt :Float = 0;

    public var next :Timestep = null;

    public function new () {}
}

private class DrawVisitor
    implements Visitor
{
    public function new () {}

    inline public function init (graphics :Graphics)
    {
        _graphics = graphics;
    }

    public function enterEntity (entity :Entity) :Bool
    {
        var didDraw = drawSprite(entity);

        // Also recurse into a Director's partially occluded scenes
        var director = entity.get(Director);
        if (director != null && didDraw) {
            for (scene in director.occludedScenes) {
                scene.visit(this, false, true);
            }
        }

        return didDraw;
    }

    public function leaveEntity (entity :Entity)
    {
        if (entity.has(Sprite)) {
            _graphics.restore();
        }
    }

    public function acceptComponent (component :Component)
    {
    }

    private function drawSprite (entity :Entity) :Bool
    {
        var sprite = entity.get(Sprite);
        if (sprite == null) {
            return true;
        }

        var alpha = sprite.alpha._;
        if (!sprite.visible || alpha <= 0) {
            return false;
        }

        _graphics.save();

        if (alpha < 1) {
            _graphics.multiplyAlpha(alpha);
        }

        if (sprite.blendMode != null) {
            _graphics.setBlendMode(sprite.blendMode);
        }

        var matrix = sprite.getLocalMatrix();
        _graphics.transform(matrix.m00, matrix.m10, matrix.m01, matrix.m11, matrix.m02, matrix.m12);

        sprite.draw(_graphics);
        return true;
    }

    private var _graphics :Graphics = null;
}
