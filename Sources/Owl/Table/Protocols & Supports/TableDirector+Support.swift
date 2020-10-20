//
//  Owl
//  A declarative type-safe framework for building fast and flexible list with Tables & Collections
//
//  Created by Daniele Margutti
//   - Web: https://www.danielemargutti.com
//   - Twitter: https://twitter.com/danielemargutti
//   - Mail: hello@danielemargutti.com
//
//  Copyright © 2019 Daniele Margutti. Licensed under Apache 2.0 License.
//

import UIKit

// MARK: - Public Supporting Structures -

public extension TableDirector {

	/// Events you can monitor from the director and related to the table
	struct TableEventsHandler {		
    private var _contextMenuPreview: ((_ context: AnyObject) -> AnyObject?)? = nil
    @available(iOS 13.0, *)
    public var contextMenuPreview: ((_ context: UIContextMenuConfiguration) -> UITargetedPreview?)? {
      get { _contextMenuPreview as? ((_ context: UIContextMenuConfiguration) -> UITargetedPreview?)? ?? nil }
      set {
        if let contextMenuPreview = newValue as? ((AnyObject) -> AnyObject?)? {
          _contextMenuPreview = contextMenuPreview
        }
      }
    }
  }

	/// Height of the row
	///
	/// - `default`: both `rowHeight`,`estimatedRowHeight` are set to `UITableViewAutomaticDimension`
	/// - automatic: automatic using autolayout. You can provide a valid estimated value.
	/// - fixed: fixed value. If all of your cells are the same height set it to fixed in order to improve the performance of the table.
	enum RowHeight {
		case `default`
		case auto(estimated: CGFloat)
		case explicit(CGFloat)
	}
	
}

// MARK: - Private Supporting Structures -

internal extension TableDirector {

	class PrefetchModelsGroup {
		let adapter: TableCellAdapterProtocol
		var models: [ElementRepresentable] = []
		var indexPaths: [IndexPath] = []

		init(adapter: TableCellAdapterProtocol) {
			self.adapter = adapter
		}
	}

}
