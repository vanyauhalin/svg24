import {
  action,
  computed,
  makeObservable,
  observable,
} from 'mobx';
import type { LogosStore } from 'types/logos';

export function initSentinel(this: LogosStore): void {
  this.sentinel = {
    _isVisible: false,
    get isVisible() {
      return this._isVisible;
    },
    set isVisible(val) {
      this._isVisible = val;
    },
    show() {
      this.isVisible = true;
    },
    hide() {
      this.isVisible = false;
    },
  };

  makeObservable(this.sentinel, {
    _isVisible: observable,
    isVisible: computed,
    show: action,
    hide: action,
  });
}
