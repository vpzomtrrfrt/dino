using Gtk;

public class Dino.Ui.DtmfPopover : Popover {
	private CallWindow call_window;

	public DtmfPopover(CallWindow call_window) {
		this.call_window = call_window;

		Box box = new Box(Orientation.VERTICAL, 15);
		box.append(create_keypad());

		this.child = box;
	}

	private Widget create_keypad() {
		Grid keypad = new Grid();

		keypad.attach(new DtmfButton(this, 1, "1"), 0, 0);
		keypad.attach(new DtmfButton(this, 2, "2"), 1, 0);
		keypad.attach(new DtmfButton(this, 3, "3"), 2, 0);
		keypad.attach(new DtmfButton(this, 4, "4"), 0, 1);
		keypad.attach(new DtmfButton(this, 5, "5"), 1, 1);
		keypad.attach(new DtmfButton(this, 6, "6"), 2, 1);
		keypad.attach(new DtmfButton(this, 7, "7"), 0, 2);
		keypad.attach(new DtmfButton(this, 8, "8"), 1, 2);
		keypad.attach(new DtmfButton(this, 9, "9"), 2, 2);
		keypad.attach(new DtmfButton(this, 10, "*"), 0, 3);
		keypad.attach(new DtmfButton(this, 0, "0"), 1, 3);
		keypad.attach(new DtmfButton(this, 11, "#"), 2, 3);

		return keypad;
	}

	private class DtmfButton : Button {
		private CallWindow call_window;
		private int number;

		public DtmfButton(DtmfPopover popover, int number, string label) {
			this.number = number;
			this.call_window = popover.call_window;

			this.label = label;
			this.clicked.connect(on_click);
		}

		private void on_click() {
			call_window.controller.send_dtmf(number);
		}
	}
}
