// Paper primitives: the handful of components every PHYSIOPAÑO screen is
// built from. Keep screens composed of these rather than ad-hoc decoration.

import 'package:flutter/material.dart';

import '../motion/springs.dart';
import 'physiopano_tokens.dart';

PpColors ppc(BuildContext context) => Theme.of(context).extension<PpColors>()!;

/// Raised paper: same colour as the ground, lifted by a warm shadow and a
/// white hairline. The default container for grouped content.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = PpRadius.panel,
    this.onTap,
    this.color,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: PpShadow.edge(c),
        boxShadow: PpShadow.raised(c),
      ),
      child: child,
    );
    return onTap == null ? card : SpringPress(onTap: onTap, pressedScale: 0.98, child: card);
  }
}

/// The one dark feature card per screen: ink ground, paper text, blue CTA.
class InkCard extends StatelessWidget {
  const InkCard({super.key, required this.child, this.padding = const EdgeInsets.all(24)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(PpRadius.panel + 4),
        boxShadow: [
          BoxShadow(color: c.panel.withValues(alpha: 0.28), blurRadius: 36, spreadRadius: -14, offset: const Offset(0, 20)),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Cool grey note with an outline icon: privacy notes, previews, caveats.
class InfoNote extends StatelessWidget {
  const InfoNote({super.key, required this.icon, required this.body, this.title});

  final IconData icon;
  final String? title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
      decoration: BoxDecoration(
        color: c.surfaceSunk,
        borderRadius: BorderRadius.circular(PpRadius.panel - 4),
        border: PpShadow.edge(c),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: title == null ? c.inkMuted : c.brand),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: t.titleMedium),
                  const SizedBox(height: 4),
                ],
                Text(body, style: t.bodyMedium?.copyWith(color: c.inkMuted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Eyebrow + tight headline + optional lede. The opening of every screen.
class PaperHeading extends StatelessWidget {
  const PaperHeading({
    super.key,
    this.eyebrow,
    required this.title,
    this.lede,
    this.titleStyle,
    this.eyebrowColor,
  });

  final String? eyebrow;
  final String title;
  final String? lede;
  final TextStyle? titleStyle;
  final Color? eyebrowColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(eyebrow!.toUpperCase(), style: PpTheme.eyebrow(context, color: eyebrowColor)),
          const SizedBox(height: 10),
        ],
        Text(title, style: titleStyle ?? t.headlineLarge),
        if (lede != null) ...[
          const SizedBox(height: 10),
          Text(lede!, style: t.bodyLarge),
        ],
      ],
    );
  }
}

enum PillTone { primary, paper, ink }

/// Pill button. Primary: blue with a soft top sheen and a blue glow.
/// Paper: raised paper pill. Ink: dark pill (for use on paper hero areas).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.tone = PillTone.primary,
    this.expand = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final PillTone tone;
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final enabled = onPressed != null && !busy;
    final (Color fg, BoxDecoration deco) = switch (tone) {
      PillTone.primary => (
          c.onBrand,
          BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(c.brand, Colors.white, 0.14)!, c.brand],
            ),
            borderRadius: BorderRadius.circular(PpRadius.pill),
            boxShadow: enabled ? PpShadow.brand(c) : null,
          )
        ),
      PillTone.paper => (
          c.ink,
          BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PpRadius.pill),
            border: PpShadow.edge(c),
            boxShadow: PpShadow.raised(c, lift: 0.6),
          )
        ),
      PillTone.ink => (
          c.onPanel,
          BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(PpRadius.pill)),
        ),
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if (busy || icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: PpTheme.font(size: 16, weight: FontWeight.w700, color: fg, spacing: -0.2),
          ),
        ),
        if (trailingIcon != null) ...[const SizedBox(width: 10), Icon(trailingIcon, size: 20, color: fg)],
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        duration: PpMotion.base,
        opacity: enabled || busy ? 1 : 0.45,
        child: SpringPress(
          onTap: enabled ? onPressed : null,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: deco,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Filter / choice chip. Selected: filled blue with glow. Otherwise raised paper.
class PaperChip extends StatelessWidget {
  const PaperChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    return Semantics(
      selected: selected,
      button: true,
      child: SpringPress(
        onTap: onTap,
        pressedScale: 0.94,
        child: AnimatedContainer(
          duration: PpMotion.base,
          curve: PpMotion.ease,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? c.brand : c.surface,
            borderRadius: BorderRadius.circular(PpRadius.pill),
            border: selected ? null : PpShadow.edge(c),
            boxShadow: selected ? PpShadow.brand(c) : PpShadow.raised(c, lift: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: selected ? c.onBrand : c.inkMuted),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: PpTheme.font(size: 14.5, weight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? c.onBrand : c.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blue rounded-square app mark, like an app icon resting on paper.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, this.size = 52, this.icon});

  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(size * 0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: icon == null
              ? const [Color(0xFFF3FAFF), Color(0xFFD9F0FF)]
              : [Color.lerp(c.brand, Colors.white, 0.12)!, c.brand],
        ),
        shadows: [
          ...PpShadow.brand(c),
          BoxShadow(color: c.highlight, blurRadius: 10, offset: const Offset(-3, -3)),
        ],
      ),
      child: icon == null
          ? Padding(
              padding: EdgeInsets.all(size * 0.06),
              child: Image.asset('assets/mascot/calm.png', excludeFromSemantics: true),
            )
          : Icon(icon, color: c.onBrand, size: size * 0.5),
    );
  }
}

/// Round raised paper button for top-bar actions (profile, theme, device).
class RoundPaperButton extends StatelessWidget {
  const RoundPaperButton({super.key, required this.icon, required this.onTap, this.tooltip, this.size = 48, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    final button = SpringPress(
      onTap: onTap,
      pressedScale: 0.88,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: PpShadow.edge(c),
          boxShadow: PpShadow.raised(c, lift: 0.6),
        ),
        child: Icon(icon, size: size * 0.44, color: active ? c.brand : c.ink),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Section title row: bold title, optional quiet caption on the right.
class PaperSectionTitle extends StatelessWidget {
  const PaperSectionTitle({super.key, required this.title, this.caption, this.action});

  final String title;
  final String? caption;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.headlineSmall),
                if (caption != null) ...[const SizedBox(height: 4), Text(caption!, style: t.bodySmall)],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
