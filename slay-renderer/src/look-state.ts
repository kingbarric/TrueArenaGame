import type { Look } from './types';

// A failed apply may leave a partial scene. Only a fully applied look can be saved.
export class LookState {
  private rendered?: Look;
  async apply(look: Look, render: () => Promise<void>): Promise<void> {
    this.rendered = undefined;
    await render();
    this.rendered = look;
  }
  requireRendered(): Look {
    if (!this.rendered) throw Error('Wait for the complete look to load before saving');
    return this.rendered;
  }
}
